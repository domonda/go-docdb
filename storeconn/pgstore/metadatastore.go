package pgstore

import (
	"context"
	"errors"
	"maps"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-sqldb"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb"
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
// checks them.
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
// has at most one successor. Postgres names the violated index in the error, so
// this is how a concurrent append is told apart from a plain duplicate. It must
// match the index name in schema/document_version.sql.
const oneSuccessorPerVersionIndex = "document_version_one_successor_per_version_idx"

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
	return db.TransactionSavepointResult(ctx, func(ctx context.Context) (*docdb.VersionInfo, error) {
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
			return info, store.assertStoredVersionEquals(ctx, info)
		}

		// A version inserted between two existing ones takes over the successor
		// that currently chains off the same predecessor — the merge-restore of
		// a deleted middle version, whose successor DeleteDocumentVersion
		// relinked to the predecessor when the version was removed. Without
		// this the successor keeps naming a predecessor that is no longer the
		// version before it, and the chain forks.
		//
		// Only a successor *after* the new version is relinked, which is what
		// separates filling in a middle version from a concurrent append: a
		// second writer appending to the same predecessor produces a version
		// after the one already there, relinks nothing, and is refused below.
		if in.PreviousVersion != nil {
			err := db.Exec(ctx,
				/* sql */ `
					update docdb.document_version
					set prev_version = $3
					where document_id = $1 and prev_version = $2 and version > $3
				`,
				in.DocID,            // $1
				*in.PreviousVersion, // $2
				in.NewVersion,       // $3
			)
			if err != nil {
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
			// The successor index is the only one that means something other
			// than "this already exists": another writer appended a version
			// after the same predecessor between this call reading the latest
			// version and inserting, so the file set carried forward here is
			// already stale. That is an optimistic concurrency conflict, and
			// the caller has to redo the work from the new latest version
			// rather than treat its own version as written.
			//
			// Of the other two, a genesis insert (PreviousVersion == nil) can
			// violate either the timestamp constraint or the genesis index —
			// both mean the document already exists. An appended insert can
			// only hit (document_id, version), meaning that specific version
			// already exists.
			var uniqueViolation sqldb.ErrUniqueViolation
			if errors.As(err, &uniqueViolation) {
				switch {
				case uniqueViolation.Constraint == oneSuccessorPerVersionIndex && in.PreviousVersion != nil:
					return nil, docdb.NewErrDocumentChanged(in.DocID, *in.PreviousVersion)
				case in.PreviousVersion == nil:
					return nil, docdb.NewErrDocumentAlreadyExists(in.DocID)
				default:
					return nil, docdb.NewErrVersionAlreadyExists(in.DocID, in.NewVersion)
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
func (store *postgresMetadataStore) assertStoredVersionEquals(ctx context.Context, expected *docdb.VersionInfo) error {
	stored, err := store.DocumentVersionInfo(ctx, expected.DocID, expected.Version)
	if err != nil {
		return errs.Errorf("assumed document %s version %s to exist in the MetadataStore: %w", expected.DocID, expected.Version, err)
	}
	normalize := commitUserIDNormalizerFromContext(ctx)
	stored = versionInfoWithNormalizedCommitUserID(stored, normalize)
	expected = versionInfoWithNormalizedCommitUserID(expected, normalize)
	if !stored.Equal(expected) {
		return errs.Errorf(
			"stored document %s version %s does not match what would have been inserted:\n\tstored:   %#v\n\texpected: %#v",
			expected.DocID, expected.Version, stored, expected,
		)
	}
	return nil
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
	// distinct because a company has one row per document version; ordered by
	// company_id for a consistent order across calls.
	return db.QueryRowsAsSlice[uu.ID](ctx,
		/* sql */ `
			select distinct company_id
			from docdb.document_version
			order by company_id
		`,
	)
}

func (store *postgresMetadataStore) CompanyDocumentIDs(ctx context.Context, companyID uu.ID) (uu.IDSlice, error) {
	// distinct because a document has one row per version; ordered by
	// document_id for a consistent order across calls.
	return db.QueryRowsAsSlice[uu.ID](ctx,
		/* sql */ `
			select distinct document_id
			from docdb.document_version
			where company_id = $1
			order by document_id
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

	deleted, err := db.QueryRowAs[bool](ctx,
		/* sql */ `
			delete from docdb.document_version
			where document_id = $1
			returning true
		`,
		docID, // $1
	)
	if err != nil {
		return err
	}
	if !deleted {
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
