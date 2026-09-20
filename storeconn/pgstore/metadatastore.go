package pgstore

import (
	"context"
	"errors"
	"fmt"
	"maps"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-sqldb"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/uu"
	rootlog "github.com/domonda/golog/log"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/internal/ctxflag"
	"github.com/domonda/go-docdb/storeconn"
)

type metadataStoreVersionsExistCtxKey struct{}

type commitUserIDNormalizerCtxKey struct{}

// CommitUserIDNormalizer maps a commit user ID to the value stored in Postgres.
// Importers use this during versions-exist sync when the file store still
// records a user ID that no longer exists in public.user.
type CommitUserIDNormalizer func(userID uu.ID) uu.ID

// ContextWithCommitUserIDNormalizer returns a context that normalizes
// CommitUserID on both sides before versions-exist metadata comparison.
func ContextWithCommitUserIDNormalizer(parent context.Context, normalize CommitUserIDNormalizer) context.Context {
	return context.WithValue(parent, commitUserIDNormalizerCtxKey{}, normalize)
}

func commitUserIDNormalizerFromContext(ctx context.Context) CommitUserIDNormalizer {
	normalize, _ := ctx.Value(commitUserIDNormalizerCtxKey{}).(CommitUserIDNormalizer)
	return normalize
}

func versionInfoWithNormalizedCommitUserID(vi *docdb.VersionInfo, normalize CommitUserIDNormalizer) *docdb.VersionInfo {
	if normalize == nil {
		return vi
	}
	normalized := *vi
	normalized.CommitUserID = normalize(vi.CommitUserID)
	return &normalized
}

// ContextWithMetadataStoreVersionsExist returns a context that switches the
// postgresMetadataStore into versions-exist mode.
//
// In that mode the MetadataStore is treated as immutable: it neither creates
// nor deletes any document versions, it only assumes they already exist and
// checks them. The one thing it may still write is the record of an existing
// version's files, and only under docdb.ContextWithFileContentWinsOverVersionInfo,
// which declares that record stale rather than authoritative — see
// reconcileStoredVersionFileRecords.
//   - CreateDocumentVersion inserts nothing; it verifies that the already-stored
//     version is identical to what it would otherwise have inserted, returning an
//     error if the version is missing or any field differs.
//   - DeleteDocument and DeleteDocumentVersion delete nothing; they verify the
//     document or version exists (returning ErrDocumentNotFound if not) and,
//     for DeleteDocumentVersion, report the same leftVersions and blob hashes a
//     real delete would, so the caller can still clean up the DocumentStore.
//
// This is meant for copying documents from one store to another where the
// DocumentStore differs but the MetadataStore already contains the document
// versions. For example, when migrating only the file blobs to a new
// DocumentStore while reusing the shared Postgres MetadataStore, the copy still
// drives the DocumentStore to write (and on rollback delete) the blobs, while
// the shared metadata is only read and verified, never mutated.
func ContextWithMetadataStoreVersionsExist(parent context.Context) context.Context {
	return context.WithValue(parent, metadataStoreVersionsExistCtxKey{}, struct{}{})
}

// metadataStoreVersionsExist reports whether ctx was derived from
// ContextWithMetadataStoreVersionsExist, putting the MetadataStore into
// the immutable versions-exist (check-only) mode.
func metadataStoreVersionsExist(ctx context.Context) bool {
	return ctx.Value(metadataStoreVersionsExistCtxKey{}) != nil
}

// oneSuccessorPerVersionIndex is the unique index on
// docdb.document_version (document_id, prev_version) enforcing that a version
// has at most one successor. Postgres names the violated index in the error,
// which is how an insert refused by this one is told apart from an insert
// refused by (document_id, version) — the latter being conclusive on its own,
// this one not (see resolveSuccessorIndexViolation). It must match the index
// name in schema/document_version.sql.
const oneSuccessorPerVersionIndex = "document_version_one_successor_per_version_idx"

var log = rootlog.NewPackageLogger()

// errSuccessorIndexViolation marks an insert that Postgres rejected naming
// oneSuccessorPerVersionIndex, which on its own does not say what happened.
// It never reaches a caller: CreateDocumentVersion replaces it with the
// caller-facing error once the savepoint is rolled back (see
// resolveSuccessorIndexViolation).
var errSuccessorIndexViolation = errs.New("one-successor-per-version index violated")

func NewMetadataStore() storeconn.MetadataStore {
	return &postgresMetadataStore{}
}

type postgresMetadataStore struct{}

// CreateDocumentVersion writes the metadata for a new document version (the
// document_version row plus its document_version_file rows) and returns the
// resulting VersionInfo.
//
// If the context carries the versions-exist flag (see
// ContextWithMetadataStoreVersionsExist), nothing is inserted; instead the
// already-stored version is queried and verified to be identical to what would
// otherwise have been inserted.
//
// The insert runs in a savepoint when the caller is already in a transaction,
// because ErrVersionAlreadyExists and ErrDocumentAlreadyExists are answers this
// method is expected to give, not just failures: storeconn.RestoreDocument
// resumes a copy whose metadata was written but whose file content was not by
// calling this for a version it knows is stored and continuing past the
// rejection. Both errors come from a unique violation, and a violation raised
// directly in the caller's transaction aborts that whole transaction — every
// later statement, of the restore and of whatever else the caller is doing,
// then fails with "current transaction is aborted". Rolling back to a savepoint
// contains the violation so only the insert is undone.
func (store *postgresMetadataStore) CreateDocumentVersion(ctx context.Context, in storeconn.CreateDocumentVersionInput) (*docdb.VersionInfo, error) {
	// Written inside the transaction below, logged after it, see
	// versionRecordCorrection.
	var correction *versionRecordCorrection

	info, err := db.TransactionSavepointResult(ctx, func(ctx context.Context) (*docdb.VersionInfo, error) {
		// Determine the full file set of the new version. When the caller already
		// computed it (in.Files), use it directly and skip the predecessor lookup
		// and re-derivation. Otherwise carry the previous version's files forward
		// (none for the first version), then apply removed/added/modified on top.
		files := in.Files
		if files == nil {
			files = make(map[string]docdb.FileInfo)
			if in.PreviousVersion != nil {
				// Look the previous version up via DocumentVersionInfo so a
				// genuinely missing predecessor surfaces as a not-found error
				// instead of silently contributing no carried-forward files. A
				// previous version that exists but has no files is fine.
				prevInfo, err := store.DocumentVersionInfo(ctx, in.DocID, *in.PreviousVersion)
				if err != nil {
					return nil, errs.Errorf("cannot carry files forward into document %s version %s: %w", in.DocID, in.NewVersion, err)
				}
				maps.Copy(files, prevInfo.Files)
			}
			for _, name := range in.RemovedFiles {
				delete(files, name)
			}
			for _, fi := range in.AddedFiles {
				files[fi.Name] = *fi
			}
			for _, fi := range in.ModifiedFiles {
				files[fi.Name] = *fi
			}
		}

		addedFilenames := namesFromFileInfos(in.AddedFiles)
		modifiedFilenames := namesFromFileInfos(in.ModifiedFiles)

		info := &docdb.VersionInfo{
			DocID:         in.DocID,
			CompanyID:     in.CompanyID,
			Version:       in.NewVersion,
			PrevVersion:   in.PreviousVersion,
			CommitUserID:  in.UserID,
			CommitReason:  in.Reason,
			AddedFiles:    addedFilenames,
			RemovedFiles:  in.RemovedFiles,
			ModifiedFiles: modifiedFilenames,
			Files:         files,
		}

		// In versions-exist mode the version is already stored (see
		// ContextWithMetadataStoreVersionsExist): insert nothing, just verify the
		// stored version matches what would have been inserted.
		if metadataStoreVersionsExist(ctx) {
			var err error
			correction, err = store.assertStoredVersionEquals(ctx, info)
			return info, err
		}

		// A version filled into an existing chain takes over the successor that
		// currently chains off the same predecessor — the merge-restore of a
		// deleted middle version, whose successor DeleteDocumentVersion
		// relinked to the predecessor when the version was removed. Without
		// this the successor keeps naming a predecessor that is no longer the
		// version before it, and the chain forks.
		//
		// Only the version the caller names is relinked, and only while it
		// still chains off the same predecessor. Nothing about a row identifies
		// it as this version's successor: a concurrent append and a
		// destination-only version of a merge-restore both name the same
		// predecessor and can sort after the new version, and adopting either
		// one leaves it naming a predecessor whose file set it never derived
		// from (see CreateDocumentVersionInput.RelinkSuccessor). An append
		// names no successor, relinks nothing, and is refused by the
		// one-successor-per-version index below.
		//
		// A named successor that is not stored, or no longer chains off
		// in.PreviousVersion, matches no row and relinks nothing.
		if in.RelinkSuccessor != nil && in.PreviousVersion != nil {
			err := db.Exec(ctx,
				/* sql */ `
					update docdb.document_version
					set prev_version = $3
					where document_id = $1 and prev_version = $2 and version = $4
				`,
				in.DocID,            // $1
				*in.PreviousVersion, // $2
				in.NewVersion,       // $3
				*in.RelinkSuccessor, // $4
			)
			if err != nil {
				// The relink violates the one-successor-per-version index
				// itself when some row already chains off in.NewVersion, which
				// a partially applied restore or a hand-repaired chain can
				// leave behind. The chain on disk is then not the one this call
				// read, which is what ErrDocumentChanged says; returning the
				// raw violation handed the caller a Postgres index name and no
				// way to tell it apart from a failure it must not retry.
				var uniqueViolation sqldb.ErrUniqueViolation
				if errors.As(err, &uniqueViolation) {
					return nil, docdb.NewErrDocumentChanged(in.DocID, *in.PreviousVersion)
				}
				return nil, err
			}
		}

		versionID := uu.IDv7()
		err := db.InsertRowStruct(ctx, &DocumentVersion{
			ID:            versionID,
			DocumentID:    in.DocID,
			CompanyID:     in.CompanyID,
			Version:       in.NewVersion,
			PrevVersion:   in.PreviousVersion, // nil => NULL
			CommitUserID:  in.UserID,
			CommitReason:  in.Reason,
			AddedFiles:    addedFilenames,
			RemovedFiles:  in.RemovedFiles,
			ModifiedFiles: modifiedFilenames,
		})
		if err != nil {
			// document_version has three unique constraints: (document_id,
			// version), a partial unique index on (document_id) where
			// prev_version is null (one genesis version per document), and
			// (document_id, prev_version) (one successor per version).
			//
			// A genesis insert (PreviousVersion == nil) can violate either the
			// timestamp constraint or the genesis index, and both mean the
			// document already exists. It can never violate the successor
			// index, whose NULL prev_version rows are all distinct.
			//
			// For an appended insert, (document_id, version) being named is
			// conclusive on its own: that specific version is stored, whether
			// or not the successor index is violated too. The successor index
			// being named is not conclusive, because a row duplicating an
			// already-stored version violates both and Postgres names whichever
			// it checks first — resolveSuccessorIndexViolation asks instead.
			var uniqueViolation sqldb.ErrUniqueViolation
			if errors.As(err, &uniqueViolation) {
				switch {
				case in.PreviousVersion == nil:
					return nil, docdb.NewErrDocumentAlreadyExists(in.DocID)
				case uniqueViolation.Constraint != oneSuccessorPerVersionIndex:
					return nil, docdb.NewErrVersionAlreadyExists(in.DocID, in.NewVersion)
				default:
					return nil, errSuccessorIndexViolation
				}
			}
			return nil, err
		}

		versionFiles := make([]*DocumentVersionFile, 0, len(files))
		for _, fi := range files {
			versionFiles = append(versionFiles, &DocumentVersionFile{
				DocumentVersionID: versionID,
				Name:              fi.Name,
				Size:              fi.Size,
				Hash:              fi.Hash,
			})
		}
		err = db.InsertRowStructs(ctx, versionFiles)
		if err != nil {
			return nil, err
		}
		return info, nil
	})
	if errors.Is(err, errSuccessorIndexViolation) {
		return nil, store.resolveSuccessorIndexViolation(ctx, in)
	}
	if err == nil {
		correction.log(ctx)
	}
	return info, err
}

// resolveSuccessorIndexViolation reports what a violation of
// oneSuccessorPerVersionIndex means for the insert of in.
//
// A row that duplicates an already-stored version violates both
// (document_id, version) and (document_id, prev_version), and which of the two
// Postgres names is its own choice: it reports the first index it checks, in
// the relation's index order. Nothing pins that order — a REINDEX or a
// dump/restore can change it — so the version is looked up instead of trusting
// the name. The insert duplicates a version that is already stored (which is
// what a resumed restore provokes on purpose and continues past), or it appends
// after a predecessor another writer has already appended to, which is the
// optimistic concurrency conflict the index exists to refuse.
//
// Called after the savepoint has been rolled back: the violation left the
// transaction aborted, so a query issued before the rollback would fail with
// "current transaction is aborted, commands ignored until end of transaction
// block" instead of answering.
func (store *postgresMetadataStore) resolveSuccessorIndexViolation(ctx context.Context, in storeconn.CreateDocumentVersionInput) error {
	stored, err := db.QueryRowAs[bool](ctx,
		/* sql */ `
			select exists(
				select from docdb.document_version
				where document_id = $1 and version = $2
			)
		`,
		in.DocID,      // $1
		in.NewVersion, // $2
	)
	if err != nil {
		return errs.Errorf("cannot tell a duplicate of document %s version %s from a concurrent append: %w", in.DocID, in.NewVersion, err)
	}
	if stored {
		return docdb.NewErrVersionAlreadyExists(in.DocID, in.NewVersion)
	}
	return docdb.NewErrDocumentChanged(in.DocID, *in.PreviousVersion)
}

// assertStoredVersionEquals verifies that the document version already stored in
// the MetadataStore is identical to expected, returning an error if the version
// is missing or differs. It backs CreateDocumentVersion's versions-exist mode.
//
// Equality is defined by docdb.VersionInfo.Equal: the scalar metadata and the
// resolved file set are compared exactly, while the added/modified/removed
// filename lists are compared order-insensitively (callers derive them from map
// iteration, so their order is not significant). When the context carries a
// CommitUserIDNormalizer, both sides are normalized before comparison.
//
// Under docdb.ContextWithFileContentWinsOverVersionInfo a difference that is
// only the record of the files' content is not a mismatch but the stale record
// that mode exists to correct, and is written instead of returned. What was
// written comes back for the caller to log once the transaction it was part of
// has returned, see versionRecordCorrection.
func (store *postgresMetadataStore) assertStoredVersionEquals(ctx context.Context, expected *docdb.VersionInfo) (correction *versionRecordCorrection, err error) {
	stored, err := store.DocumentVersionInfo(ctx, expected.DocID, expected.Version)
	if err != nil {
		return nil, errs.Errorf("assumed document %s version %s to exist in the MetadataStore: %w", expected.DocID, expected.Version, err)
	}
	normalize := commitUserIDNormalizerFromContext(ctx)
	stored = versionInfoWithNormalizedCommitUserID(stored, normalize)
	expected = versionInfoWithNormalizedCommitUserID(expected, normalize)
	if stored.Equal(expected) {
		return nil, nil
	}
	if ctxflag.FileContentWinsOverVersionInfo(ctx) {
		correction, err = store.reconcileStoredVersionFileRecords(ctx, stored, expected)
		if err != nil {
			return nil, err
		}
		if correction != nil {
			return correction, nil
		}
	}
	return nil, errs.Errorf(
		"stored document %s version %s does not match what would have been inserted:\n\tstored:   %#v\n\texpected: %#v",
		expected.DocID, expected.Version, stored, expected,
	)
}

// versionRecordCorrection is what reconcileStoredVersionFileRecords wrote, kept
// for CreateDocumentVersion to log once the transaction those writes are part
// of has returned without error.
//
// The record is not logged where it is written. What it holds is the only
// surviving account of the values it overwrote, so it must not describe a write
// that never landed: the delta update can still fail after the last file
// correction, and a caller's transaction can fail after this store is done with
// it, and either rolls the corrections back while the line claiming them stays
// in the log.
//
// One case it cannot cover: in a transaction the caller opened, the writes end
// at a released savepoint rather than at a commit, and an outer rollback can
// still undo what the line reports. Nothing tells this store when that
// transaction ends. Logging after the savepoint is wrong only for a caller that
// rolls back afterwards; logging before the write was wrong for every caller.
type versionRecordCorrection struct {
	docID          uu.ID
	version        docdb.VersionTime
	correctedFiles []string
	corrections    []string
	addedFiles     []string
	modifiedFiles  []string
	removedFiles   []string
}

// log writes the audit record of a correction. A nil receiver writes nothing,
// which is the version that needed none.
func (c *versionRecordCorrection) log(ctx context.Context) {
	if c == nil {
		return
	}
	// The delta lists are logged too, not only the corrected files: they are
	// written whenever a correction happens at all, so a version whose own file
	// records were already right has an empty correctedFiles and that write as
	// the only thing that happened to it.
	log.ErrorCtx(ctx, "Corrected the stored record of a document version to the file content it is restored with").
		UUID("docID", c.docID).
		Stringer("version", c.version).
		Strs("correctedFiles", c.correctedFiles).
		Strs("corrections", c.corrections).
		Strs("addedFiles", c.addedFiles).
		Strs("modifiedFiles", c.modifiedFiles).
		Strs("removedFiles", c.removedFiles).
		Log()
}

// reconcileStoredVersionFileRecords corrects the stored record of a version's
// files to the content the version being restored actually has, and reports
// whether it did.
//
// It is the MetadataStore half of docdb.ContextWithFileContentWinsOverVersionInfo.
// Reading a file whose recorded size or hash is stale is only half of a
// migration: this store keeps a second record of the same files in
// docdb.document_version_file, and for a document whose versions were mirrored
// here from the source store that record was written from the same stale
// version info. Versions-exist mode compares the version derived from the
// content against it, so without this the corrected read is refused here
// instead of in docdb.ReadHashedDocument — the same document, one layer down.
//
// Only a disagreement about the content of files both sides name is corrected.
// The two must name the same document, version, company, predecessor, commit
// user and reason, and the same set of filenames; sizes, hashes and the
// added/modified/removed name lists derived from the hashes may differ and are
// rewritten from expected. A different file set is left to the caller's error,
// because a file only one side has is content invented or dropped rather than a
// stale record of content that is there — the line docdb.ReadHashedDocument
// draws in this mode is drawn here too.
//
// It writes but does not log: the record of what it overwrote goes back to
// CreateDocumentVersion, which logs it once the transaction the writes are part
// of has returned, see versionRecordCorrection.
//
// The correction is committed when it is made, not when the restore that
// triggered it finishes. CreateDocumentVersion runs it in the caller's
// transaction when there is one and in a transaction of its own when there is
// not, and storeconn.RestoreDocument opens none — so a restore that fails at a
// later version leaves the corrections of the versions before it in place, and
// the rollback cannot take them back: it undoes a version through
// DeleteDocumentVersion, which deletes nothing in versions-exist mode. That is
// the state a rerun repairs, and it is not worse than the one before the
// correction: the record it replaced named a content hash the DocumentStore did
// not hold either. A caller that needs the correction to be undone with the
// restore has to open the transaction around it itself.
func (store *postgresMetadataStore) reconcileStoredVersionFileRecords(ctx context.Context, stored, expected *docdb.VersionInfo) (correction *versionRecordCorrection, err error) {
	if !onlyFileContentRecordsDiffer(stored, expected) {
		return nil, nil
	}

	versionID, err := db.QueryRowAs[uu.ID](ctx,
		/* sql */ `
			select id from docdb.document_version
			where document_id = $1 and version = $2
		`,
		expected.DocID,   // $1
		expected.Version, // $2
	)
	if err != nil {
		return nil, err
	}

	// What each correction overwrote is collected next to what replaced it: the
	// correction is not undone by a rollback, and the source store its value
	// was derived from is the one the migration exists to retire, so the log
	// line the caller writes from this is the only record left of what the row
	// held before.
	correctedFiles := make([]string, 0, len(expected.Files))
	corrections := make([]string, 0, len(expected.Files))
	for name, expectedFile := range expected.Files {
		storedFile := stored.Files[name]
		if storedFile == expectedFile {
			continue
		}
		err = db.Exec(ctx,
			/* sql */ `
				update docdb.document_version_file
				set size = $3, hash = $4
				where document_version_id = $1 and name = $2
			`,
			versionID,         // $1
			name,              // $2
			expectedFile.Size, // $3
			expectedFile.Hash, // $4
		)
		if err != nil {
			return nil, err
		}
		correctedFiles = append(correctedFiles, name)
		corrections = append(corrections, fmt.Sprintf(
			"%s: %d bytes %s -> %d bytes %s",
			name, storedFile.Size, storedFile.Hash, expectedFile.Size, expectedFile.Hash,
		))
	}

	// The file deltas are derived from the file hashes (see
	// docdb.VersionInfo.SetFileDeltas), so a corrected hash changes them: in
	// this version, and in the version after it, whose files are compared
	// against these. They are written whenever this function corrects anything
	// at all, including when only they differ — that is a version whose own
	// files are recorded correctly but whose deltas still describe the stale
	// hashes of its predecessor, and leaving those would refuse it here for the
	// correction applied to the version before it.
	err = db.Exec(ctx,
		/* sql */ `
			update docdb.document_version
			set added_files = $2, removed_files = $3, modified_files = $4
			where id = $1
		`,
		versionID,              // $1
		expected.AddedFiles,    // $2
		expected.RemovedFiles,  // $3
		expected.ModifiedFiles, // $4
	)
	if err != nil {
		return nil, err
	}

	return &versionRecordCorrection{
		docID:          expected.DocID,
		version:        expected.Version,
		correctedFiles: correctedFiles,
		corrections:    corrections,
		addedFiles:     expected.AddedFiles,
		modifiedFiles:  expected.ModifiedFiles,
		removedFiles:   expected.RemovedFiles,
	}, nil
}

// onlyFileContentRecordsDiffer reports whether stored and expected describe the
// same version of the same document with the same filenames, so that whatever
// differs between them is the record of those files' content: their sizes and
// hashes, and the added/modified/removed name lists derived from the hashes.
//
// Everything but that record is compared by docdb.VersionInfo.Equal rather than
// by a field list repeated here. This is the gate that authorizes overwriting
// stored rows, and a field added to VersionInfo later would silently not be
// compared by a restatement — a version differing in exactly that field would
// pass as one whose file records are merely stale and have its record rewritten
// instead of being refused.
//
// The commit user ID is compared as the caller normalized it, see
// versionInfoWithNormalizedCommitUserID.
func onlyFileContentRecordsDiffer(stored, expected *docdb.VersionInfo) bool {
	if len(stored.Files) != len(expected.Files) {
		return false
	}
	for name := range expected.Files {
		if _, ok := stored.Files[name]; !ok {
			return false
		}
	}
	// A copy of stored carrying expected's record of the files' content: what
	// Equal then compares is everything else. The copy is by value and the
	// fields replaced are the ones this function is allowed to rewrite, so
	// stored itself is not touched.
	probe := *stored
	probe.Files = expected.Files
	probe.AddedFiles = expected.AddedFiles
	probe.ModifiedFiles = expected.ModifiedFiles
	probe.RemovedFiles = expected.RemovedFiles
	return probe.Equal(expected)
}

func (store *postgresMetadataStore) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	return db.QueryRowAs[uu.ID](ctx,
		/* sql */ `
			select company_id from docdb.document_version
			where document_id = $1
			order by version desc
			limit 1
		`,
		docID, // $1
	)
}

// SetDocumentCompanyID sets the company of every version of the document, not
// only of its latest one. This store keeps no owner marker separate from the
// versions, so the company of a document is the company of its latest version;
// rewriting only that one would leave the versions before it naming a company
// the document was never moved away from by a version. A move that is meant to
// stay visible in the document's history has to be committed as a new version
// with docdb.CreateVersionResult.NewCompanyID instead.
func (store *postgresMetadataStore) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error {
	ids, err := db.QueryRowsAsSlice[uu.ID](ctx,
		/* sql */ `
			update docdb.document_version
			set company_id = $1
			where document_id = $2
			returning docdb.document_version.id
		`,
		companyID, // $1
		docID,     // $2
	)
	if err != nil {
		return err
	}

	if len(ids) == 0 {
		return docdb.NewErrDocumentNotFound(docID)
	}

	return nil
}

func (store *postgresMetadataStore) DocumentVersions(ctx context.Context, docID uu.ID) ([]docdb.VersionTime, error) {
	versions, err := db.QueryRowsAsSlice[docdb.VersionTime](ctx,
		/* sql */ `
			select version
			from docdb.document_version
			where document_id = $1
			order by version asc
		`,
		docID, // $1
	)
	if err != nil {
		return nil, err
	}

	if len(versions) == 0 {
		return nil, docdb.NewErrDocumentNotFound(docID)
	}

	return versions, nil
}

func (store *postgresMetadataStore) LatestDocumentVersion(ctx context.Context, docID uu.ID) (docdb.VersionTime, error) {
	return db.QueryRowAs[docdb.VersionTime](ctx,
		/* sql */ `
			select version
			from docdb.document_version
			where document_id = $1
			order by version desc
			limit 1
		`,
		docID, // $1
	)
}

func (store *postgresMetadataStore) CompanyIDs(ctx context.Context) (uu.IDSlice, error) {
	// A document belongs to the company of its latest version, so a company is
	// reported only while some document's latest version still names it: one
	// that every document was moved away from has no documents left, even
	// though the versions committed before those moves still name it.
	//
	// Written as a candidate list plus an exists filter, not as a reduction of
	// the whole table to one row per document (`distinct on (document_id) ...
	// order by document_id, version desc`). That reduction has to read and sort
	// every version row of every document before it can answer, which is a full
	// scan plus a sort of the whole table on every call — and this is a
	// bulk-operation and routerconn fan-out entry point. The candidate list is
	// an index-only scan of document_version_company_id_idx, and each exists
	// probe is served by the same index and stops at the first document the
	// company still owns, which for a company that owns any is its first row.
	return db.QueryRowsAsSlice[uu.ID](ctx,
		/* sql */ `
			select candidate.company_id
			from (
				select distinct company_id from docdb.document_version
			) candidate
			where exists (
				select
				from docdb.document_version dv
				where dv.company_id = candidate.company_id
					and dv.version = (
						select max(later.version)
						from docdb.document_version later
						where later.document_id = dv.document_id
					)
			)
			order by candidate.company_id
		`,
	)
}

func (store *postgresMetadataStore) CompanyDocumentIDs(ctx context.Context, companyID uu.ID) (uu.IDSlice, error) {
	// A document belongs to the company of its latest version, so a document
	// moved to another company is no longer listed under the previous one, even
	// though the versions committed before the move still name it. Selecting
	// every row with the company and deduplicating by document instead would
	// list a moved document under both companies, and a bulk operation over a
	// company would then process documents it does not own.
	//
	// The company predicate is applied first so only the rows of the passed
	// company are checked for being the latest version of their document
	// (document_version_company_id_idx), rather than reducing the whole table
	// to one row per document. Ordered by document_id for a consistent order
	// across calls.
	return db.QueryRowsAsSlice[uu.ID](ctx,
		/* sql */ `
			select dv.document_id
			from docdb.document_version dv
			where dv.company_id = $1
				and dv.version = (
					select max(later.version)
					from docdb.document_version later
					where later.document_id = dv.document_id
				)
			order by dv.document_id
		`,
		companyID, // $1
	)
}

func (store *postgresMetadataStore) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error) {
	records, err := db.QueryRowsAsSlice[docVersionQueryResult](
		ctx,
		/* sql */ `
			select *
			from docdb.document_version dv
			left join docdb.document_version_file dvf on dv.id = dvf.document_version_id
			where dv.document_id = $1 and dv.version = $2
		`,
		docID,   // $1
		version, // $2
	)
	if err != nil {
		return nil, err
	}

	if len(records) == 0 {
		return nil, docdb.NewErrDocumentNotFound(docID)
	}

	files := map[string]docdb.FileInfo{}
	for _, rec := range records {
		if rec.DocumentVersionID == nil {
			continue
		}

		files[*rec.Name] = docdb.FileInfo{
			Name: *rec.Name,
			Size: *rec.Size,
			Hash: *rec.Hash,
		}
	}

	firstRec := records[0]
	return &docdb.VersionInfo{
		CompanyID:     firstRec.CompanyID,
		DocID:         firstRec.DocumentID,
		Version:       firstRec.Version,
		PrevVersion:   firstRec.PrevVersion,
		CommitUserID:  firstRec.CommitUserID,
		CommitReason:  firstRec.CommitReason,
		AddedFiles:    firstRec.AddedFiles,
		ModifiedFiles: firstRec.ModifiedFiles,
		RemovedFiles:  firstRec.RemovedFiles,
		Files:         files,
	}, nil
}

func (store *postgresMetadataStore) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*docdb.VersionInfo, error) {
	records, err := db.QueryRowsAsSlice[docVersionQueryResult](ctx,
		/* sql */ `
			select *
			from docdb.document_version dv
			left join docdb.document_version_file dvf on dv.id = dvf.document_version_id
			where document_id = $1 and dv.version = (
				select version
				from docdb.document_version
				where document_id = $1
				order by version desc
				limit 1
			)
		`,
		docID, // $1
	)
	if err != nil {
		return nil, err
	}

	if len(records) == 0 {
		return nil, docdb.NewErrDocumentNotFound(docID)
	}

	files := map[string]docdb.FileInfo{}
	for _, rec := range records {
		if rec.DocumentVersionID == nil {
			continue
		}

		files[*rec.Name] = docdb.FileInfo{
			Name: *rec.Name,
			Size: *rec.Size,
			Hash: *rec.Hash,
		}
	}

	firstRec := records[0]
	result := &docdb.VersionInfo{
		CompanyID:     firstRec.CompanyID,
		DocID:         firstRec.DocumentID,
		Version:       firstRec.Version,
		PrevVersion:   firstRec.PrevVersion,
		CommitUserID:  firstRec.CommitUserID,
		CommitReason:  firstRec.CommitReason,
		AddedFiles:    firstRec.AddedFiles,
		ModifiedFiles: firstRec.ModifiedFiles,
		RemovedFiles:  firstRec.RemovedFiles,
		Files:         files,
	}

	return result, nil
}

type docVersionQueryResult struct {
	DocumentVersion

	DocumentVersionID *uu.ID  `db:"document_version_id"`
	Name              *string `db:"name"`
	Size              *int64  `db:"size"`
	Hash              *string `db:"hash"`
}

func (store *postgresMetadataStore) DeleteDocument(ctx context.Context, docID uu.ID) error {
	// In versions-exist mode the MetadataStore is immutable: do not delete,
	// only verify the document exists. See ContextWithMetadataStoreVersionsExist.
	if metadataStoreVersionsExist(ctx) {
		exists, err := db.QueryRowAs[bool](ctx,
			/* sql */ `
				select exists(
					select from docdb.document_version
					where document_id = $1
				)
			`,
			docID, // $1
		)
		if err != nil {
			return err
		}
		if !exists {
			return docdb.NewErrDocumentNotFound(docID)
		}
		return nil
	}

	// Counted inside a CTE rather than read from `returning`, which yields no
	// row at all for a document that is not there: QueryRowAs then fails with
	// sql.ErrNoRows instead of reaching the not-found below, and that error
	// does not match os.ErrNotExist. storeconn.DeleteDocument keys on exactly
	// that match to go on and delete the document's file content when the
	// metadata is already gone, so the raw sql.ErrNoRows stopped it and
	// orphaned the content it exists to remove — and RestoreDocument with
	// recreate=true failed instead of rebuilding such a document.
	// DeleteDocumentVersion aggregates its count the same way.
	deleted, err := db.QueryRowAs[int](ctx,
		/* sql */ `
			with deleted as (
				delete from docdb.document_version
				where document_id = $1
				returning 1
			)
			select count(*)::int from deleted
		`,
		docID, // $1
	)
	if err != nil {
		return err
	}
	if deleted == 0 {
		return docdb.NewErrDocumentNotFound(docID)
	}
	return nil
}

func (store *postgresMetadataStore) DeleteDocumentVersion(
	ctx context.Context,
	docID uu.ID,
	version docdb.VersionTime,
) (
	leftVersions []docdb.VersionTime,
	hashesToDelete []string,
	err error,
) {
	// In versions-exist mode the MetadataStore is immutable: do not delete the
	// version, only verify it exists (deleted_row then counts the still-present
	// target row instead of the deleted ones) and report the same leftVersions
	// and blob hashes a real delete would, so the caller can still clean up the
	// DocumentStore. See ContextWithMetadataStoreVersionsExist.
	targetVersionCTE := /*sql*/ `
		deleted_row as (
			delete from docdb.document_version
				where document_id = $1
				and version = $2
			returning id, prev_version
		)`
	if metadataStoreVersionsExist(ctx) {
		targetVersionCTE = /*sql*/ `
		deleted_row as (
			select id, prev_version from docdb.document_version
			where document_id = $1
			and version = $2
		)`
	}

	type Res struct {
		DeletedIDs         int                `db:"deleted_ids"`
		DeletedPrevVersion *docdb.VersionTime `db:"deleted_prev_version"`
		LeftVersions       []string           `db:"left_versions"`
		HashesToDelete     []string           `db:"hashes_to_delete"`
	}
	res, err := db.QueryRowAs[Res](ctx,
		/* sql */ `
			with
			left_versions as (
				select version from docdb.document_version
				where document_id = $1 and version != $2
				order by version
			),
			hashes_to_delete as (
				-- Hashes referenced only by the version being deleted.
				-- Files in docdb.document_version_file represent the full
				-- per-version file set (carry-forward + adds + mods), so
				-- naïvely returning every file of the deleted version would
				-- also wipe blobs still referenced by sibling versions and
				-- corrupt them on the documentStore side.
				select dvf.hash
				from docdb.document_version_file dvf
				join docdb.document_version dv
					on dvf.document_version_id = dv.id
					and dv.document_id = $1
					and dv.version = $2
				where not exists (
					select 1
					from docdb.document_version_file other_dvf
					join docdb.document_version other_dv
						on other_dvf.document_version_id = other_dv.id
						and other_dv.document_id = $1
						and other_dv.version != $2
					where other_dvf.hash = dvf.hash
				)
				order by dvf.hash
			),
			`+targetVersionCTE+ /*sql*/ `
			-- Aggregate each CTE independently so an empty left_versions
			-- or hashes_to_delete does not zero-out the deleted_ids count
			-- via Cartesian-product collapse. Cast version::text so the
			-- result column matches the []string scan target.
			select
				coalesce((select array_agg(distinct version::text) from left_versions), '{}'::text[]) as left_versions,
				coalesce((select array_agg(distinct hash) from hashes_to_delete), '{}'::text[]) as hashes_to_delete,
				(select count(*)::int from deleted_row) as deleted_ids,
				(select prev_version from deleted_row limit 1) as deleted_prev_version
		`,
		docID,   // $1
		version, // $2
	)
	if err != nil {
		return nil, nil, err
	}

	if res.DeletedIDs == 0 {
		return nil, nil, docdb.NewErrDocumentNotFound(docID)
	}

	for _, versionStr := range res.LeftVersions {
		version, err := docdb.VersionTimeFromString(versionStr)
		if err != nil {
			return nil, nil, err
		}
		leftVersions = append(leftVersions, version)
	}

	for _, hash := range res.HashesToDelete {
		hashesToDelete = append(hashesToDelete, hash)
	}

	if !metadataStoreVersionsExist(ctx) && res.DeletedPrevVersion != nil {
		// Relink successors only when a non-genesis version was deleted. Skipping
		// relink for a genesis delete leaves successors pointing at the removed
		// version so merge-restore (RestoreDocument with recreate=false) can
		// re-insert the earliest version without hitting the one-genesis-per-document
		// unique index.
		err = db.Exec(ctx,
			/* sql */ `
				update docdb.document_version
				set prev_version = $3
				where document_id = $1 and prev_version = $2
			`,
			docID,                  // $1
			version,                // $2
			res.DeletedPrevVersion, // $3
		)
		if err != nil {
			return nil, nil, err
		}
	}

	return leftVersions, hashesToDelete, nil
}

// namesFromFileInfos returns the file names of the passed FileInfos, or nil
// when none are passed. Returning nil (rather than an empty slice) keeps an
// empty added/modified list consistent with a nil removed list and stores it
// as a NULL column instead of an empty array.
func namesFromFileInfos(files []*docdb.FileInfo) (names []string) {
	if len(files) == 0 {
		return nil
	}
	names = make([]string, len(files))
	for i, fi := range files {
		names[i] = fi.Name
	}
	return names
}
