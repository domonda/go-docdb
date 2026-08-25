// Package storeconn provides a docdb.Conn implementation that combines
// a DocumentStore for file content storage with a MetadataStore
// for version metadata.
package storeconn

import (
	"context"
	"errors"
	"maps"
	"os"
	"time"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb"
)

// New returns a new docdb.Conn that uses the provided DocumentStore
// for file storage and MetadataStore for version metadata.
func New(documentStore DocumentStore, metadataStore MetadataStore) docdb.Conn {
	return &conn{
		documentStore: documentStore,
		metadataStore: metadataStore,
	}
}

type conn struct {
	documentStore DocumentStore
	metadataStore MetadataStore
}

var _ docdb.Conn = (*conn)(nil)

func (c *conn) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	return c.documentStore.DocumentExists(ctx, docID)
}

func (c *conn) DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version docdb.VersionTime) (docdb.FileProvider, error) {
	versionInfo, err := c.metadataStore.DocumentVersionInfo(ctx, docID, version)
	if err != nil {
		return nil, err
	}

	hashes := make([]string, 0, len(versionInfo.Files))
	for _, fi := range versionInfo.Files {
		hashes = append(hashes, fi.Hash)
	}

	return c.documentStore.DocumentHashFileProvider(ctx, docID, hashes)
}

func (c *conn) ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version docdb.VersionTime, filename string) (data []byte, err error) {
	versionInfo, err := c.metadataStore.DocumentVersionInfo(ctx, docID, version)
	if err != nil {
		return nil, err
	}

	fileInfo, ok := versionInfo.Files[filename]
	if !ok {
		return nil, docdb.NewErrDocumentFileNotFound(docID, filename)
	}

	return c.documentStore.ReadDocumentHashFile(ctx, docID, filename, fileInfo.Hash)
}

func (c *conn) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	return c.metadataStore.DocumentCompanyID(ctx, docID)
}

func (c *conn) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error {
	return c.metadataStore.SetDocumentCompanyID(ctx, docID, companyID)
}

func (c *conn) DocumentVersions(ctx context.Context, docID uu.ID) ([]docdb.VersionTime, error) {
	return c.metadataStore.DocumentVersions(ctx, docID)
}

func (c *conn) LatestDocumentVersion(ctx context.Context, docID uu.ID) (docdb.VersionTime, error) {
	return c.metadataStore.LatestDocumentVersion(ctx, docID)
}

func (c *conn) CompanyIDs(ctx context.Context) (uu.IDSlice, error) {
	return c.metadataStore.CompanyIDs(ctx)
}

func (c *conn) CompanyDocumentIDs(ctx context.Context, companyID uu.ID) (uu.IDSlice, error) {
	return c.metadataStore.CompanyDocumentIDs(ctx, companyID)
}

func (c *conn) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error) {
	return c.metadataStore.DocumentVersionInfo(ctx, docID, version)
}

func (c *conn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*docdb.VersionInfo, error) {
	return c.metadataStore.LatestDocumentVersionInfo(ctx, docID)
}

func (c *conn) DeleteDocument(ctx context.Context, docID uu.ID) error {
	// Both stores are asked, and only a document that neither of them holds is
	// reported as not found. They are written and deleted one after the other,
	// so a failure or a cancellation between the two steps leaves a document in
	// only one of them — file content without metadata, most of the time.
	// Returning the MetadataStore's not-found before touching the DocumentStore
	// would orphan that content permanently, because every later delete would
	// stop at the same not-found.
	metaErr := c.metadataStore.DeleteDocument(ctx, docID)
	if metaErr != nil && !errors.Is(metaErr, os.ErrNotExist) {
		return metaErr
	}
	blobErr := c.documentStore.DeleteDocument(ctx, docID)
	if blobErr != nil && !errors.Is(blobErr, os.ErrNotExist) {
		return blobErr
	}
	if metaErr != nil && blobErr != nil {
		return metaErr
	}
	return nil
}

func (c *conn) DeleteDocumentVersion(ctx context.Context, docID uu.ID, version docdb.VersionTime) (leftVersions []docdb.VersionTime, err error) {
	leftVersions, hashesToDelete, err := c.metadataStore.DeleteDocumentVersion(ctx, docID, version)
	if err != nil {
		return nil, err
	}

	err = c.documentStore.DeleteDocumentHashes(ctx, docID, hashesToDelete)
	if err != nil {
		return nil, err
	}

	return leftVersions, err
}

func (c *conn) CreateDocument(
	ctx context.Context,
	companyID uu.ID,
	docID uu.ID,
	userID uu.ID,
	reason string,
	version docdb.VersionTime,
	files []fs.FileReader,
	onNewVersion docdb.OnNewVersionFunc,
) (err error) {
	if err = version.Validate(); err != nil {
		return err
	}
	if len(files) == 0 {
		// The first version of a document must contain at least one file:
		// a document cannot start with an empty, change-less version.
		return errs.Errorf("cannot create document %s without files", docID)
	}
	if onNewVersion == nil {
		return errs.New("nil onNewVersion func passed to createDocumentVersion")
	}

	// Refuse to create a genesis document whose files already exist in the
	// documentStore. Conn.CreateDocument is documented to return
	// ErrDocumentAlreadyExists for an existing document, and proceeding would be
	// destructive: if a later step failed, the rollback below would delete blobs
	// (deduplicated by content hash) and metadata shared with the pre-existing
	// document. This must run before the rollback defer is registered so a
	// refused create never triggers that cleanup. The check targets the
	// documentStore, not the metadataStore, so copying a document into a fresh
	// documentStore that reuses an already-populated metadataStore
	// (ContextWithMetadataStoreVersionsExist) is still allowed.
	exists, existsErr := c.documentStore.DocumentExists(ctx, docID)
	if existsErr != nil {
		return existsErr
	}
	if exists {
		return docdb.NewErrDocumentAlreadyExists(docID)
	}

	var versionInfo *docdb.VersionInfo

	defer func() {
		if err == nil {
			return
		}
		// Roll back a partially created genesis document.
		//
		// Blobs: the existence guard above proved the documentStore held no files
		// for docID before this call, so every object now under docID was written
		// here and may be deleted to clean up a partial write — EXCEPT when the
		// metadata insert failed with ErrDocumentAlreadyExists. That error means
		// another writer owns the genesis version for this docID: a concurrent
		// CreateDocument that won the race for the one-genesis-per-document unique
		// index, or a pre-existing metadata-without-blobs document being
		// re-created. The objects now under docID are content-addressed and shared
		// with that winner, so deleting them would corrupt it (the existence guard
		// is exactly what the already-exists error disproves under concurrency);
		// leave the identical objects in place instead. For any other failure the
		// blobs are this call's own partial write: delete the whole document's
		// blobs rather than only the hashes the metadata insert reported, so that a
		// partial blob write — which returns no FileInfos but may already have
		// stored some objects — is cleaned up instead of orphaned. A not-found
		// result (nothing was written yet) is expected and ignored.
		cleanupCtx, cancelCleanup := rollbackCtx(ctx)
		defer cancelCleanup()
		if !errors.As(err, &docdb.ErrDocumentAlreadyExists{}) {
			delErr := c.documentStore.DeleteDocument(cleanupCtx, docID)
			if delErr != nil && !errors.Is(delErr, os.ErrNotExist) {
				err = errors.Join(err, delErr)
			}
		}
		// Metadata: delete only the single genesis version this call inserted,
		// and only if it was actually inserted (versionInfo != nil). The
		// existence guard checks the documentStore, not the metadataStore, so the
		// document may already hold versions there (a fresh documentStore reusing
		// a populated metadataStore, or an inconsistent metadata-without-blobs
		// state). DeleteDocument would wipe those unrelated versions, and deleting
		// `version` after a failed insert would wipe a pre-existing version that
		// collided with it — so target exactly the row this call added, and only
		// when it succeeded. A not-found result is ignored so a spurious
		// not-found is never joined onto the real cause.
		if versionInfo != nil {
			_, _, delErr := c.metadataStore.DeleteDocumentVersion(cleanupCtx, docID, version)
			if delErr != nil && !errors.Is(delErr, os.ErrNotExist) {
				err = errors.Join(err, delErr)
			}
		}
	}()
	// Turn a panic from a store into the error the rollback above keys on:
	// registered after it so it runs first, and deferred directly because
	// recover only recovers when the deferred function calls it itself — from
	// inside the rollback closure it would return nil and the panic would
	// escape with the partial document left behind.
	defer errs.RecoverPanicAsErrorWithFuncParams(&err, ctx, companyID, docID, userID, reason, version, files, onNewVersion)

	// Writing the blobs returns a FileInfo (name, size, content hash) per file.
	// The first version records every file as an added file, so reuse these
	// directly instead of re-reading and re-hashing the files.
	addedFiles, err := c.documentStore.CreateDocumentVersion(ctx, docID, version, files)
	if err != nil {
		return err
	}

	versionInfo, err = c.metadataStore.CreateDocumentVersion(ctx, CreateDocumentVersionInput{
		DocID:      docID,
		CompanyID:  companyID,
		UserID:     userID,
		Reason:     reason,
		NewVersion: version,
		// PreviousVersion nil: first (genesis) version
		AddedFiles: addedFiles,
	})
	if err != nil {
		return err
	}

	return onNewVersion(ctx, versionInfo)
}

func (c *conn) AddDocumentVersion(
	ctx context.Context,
	docID uu.ID,
	userID uu.ID,
	reason string,
	createVersion docdb.CreateVersionFunc,
	onNewVersion docdb.OnNewVersionFunc,
) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, userID, reason, createVersion, onNewVersion)

	if err = ctx.Err(); err != nil {
		return err
	}
	if err = docID.Validate(); err != nil {
		return err
	}
	if err = userID.Validate(); err != nil {
		return err
	}
	if createVersion == nil {
		return errs.New("nil createVersion func passed to AddDocumentVersion")
	}
	if onNewVersion == nil {
		return errs.New("nil onNewVersion func passed to AddDocumentVersion")
	}

	latestVersionInfo, err := c.metadataStore.LatestDocumentVersionInfo(ctx, docID)
	if err != nil {
		return err
	}

	hashes := make([]string, 0, len(latestVersionInfo.Files))
	for _, file := range latestVersionInfo.Files {
		hashes = append(hashes, file.Hash)
	}

	fileProvider, err := c.documentStore.DocumentHashFileProvider(ctx, docID, hashes)
	if err != nil {
		return err
	}

	result, err := safelyCallCreateVersionFunc(
		ctx,
		docID,
		latestVersionInfo.Version,
		fileProvider,
		createVersion,
	)
	if err != nil {
		return err
	}
	if err = result.Validate(); err != nil {
		return err
	}
	if !result.Version.After(latestVersionInfo.Version) {
		return errs.Errorf("version %s returned from CreateVersionFunc is not after previous version %s", result.Version, latestVersionInfo.Version)
	}

	companyID := result.NewCompanyID.GetOr(latestVersionInfo.CompanyID)

	// Compute the resulting full file set (previous files, minus the removed
	// ones, with the written ones overlaid) to enforce, before committing
	// anything, that every version contains at least one file: removing all
	// files of a document is not allowed. It is also passed to
	// CreateDocumentVersion as Files so the store does not re-query the
	// predecessor and re-derive the identical set.
	resultingFiles := make(map[string]docdb.FileInfo, len(latestVersionInfo.Files))
	maps.Copy(resultingFiles, latestVersionInfo.Files)
	for _, name := range result.RemoveFiles {
		delete(resultingFiles, name)
	}
	// The bytes read here are also what gets uploaded below, rather than
	// handing the DocumentStore the same readers to read a second time. A
	// FileReader is not guaranteed to return the same content twice — an fs.File
	// whose backing file is rewritten between the two reads is enough — and the
	// version would then record the hash of what was read here while the store
	// holds what was read there. Files are addressed by content hash, so that
	// object can never be found again under the recorded hash, and the document
	// fails every later ReadHashedDocument: silent, and only discovered at the
	// next backup or migration.
	writeFiles := make([]fs.FileReader, 0, len(result.WriteFiles))
	var data []byte
	for _, file := range result.WriteFiles {
		data, err = file.ReadAll()
		if err != nil {
			return err
		}
		writeFiles = append(writeFiles, fs.NewMemFile(file.Name(), data))
		// Size and Hash both describe the bytes that were just read, rather
		// than taking the size from a separate file.Size() stat: the two are
		// not guaranteed to see the same content — an fs.File whose content
		// changes between the read and the stat, or a FileReader whose Size()
		// simply does not match what ReadAll returns — and a version stored
		// with a Size contradicting its Hash fails every later read of it in
		// ReadHashedDocument. HashedDocument.VersionInfo records the same
		// field as int64(len(data)) for the same reason.
		resultingFiles[file.Name()] = docdb.FileInfo{Name: file.Name(), Size: int64(len(data)), Hash: docdb.ContentHash(data)}
	}
	if len(resultingFiles) == 0 {
		return errs.Errorf("cannot remove all files of document %s: every version must contain at least one file", docID)
	}

	// The change lists are derived by the shared VersionInfo.SetFileDeltas from
	// the resulting and the previous file set, so this path agrees with the
	// other implementations — a MetadataStore in versions-exist mode compares
	// the two, and localfsdb derives the same way. Classifying the written
	// files by name instead would report a file rewritten with byte-identical
	// content as modified, and a RemoveFiles entry the previous version did not
	// have as removed.
	deltas := docdb.VersionInfo{Files: resultingFiles}
	deltas.SetFileDeltas(latestVersionInfo.Files)

	// A version with the same files as its predecessor changes nothing, unless
	// it moves the document to another company: that is how a move is recorded,
	// as a version that changes nothing but the company. localfsdb has always
	// refused a change-less version this way, and docdb.Conn documents it as
	// the answer of every implementation.
	//
	// This is the only place the rule is enforced. HashedDocument.Validate
	// deliberately accepts such a version, because DeleteDocumentVersion and
	// SetDocumentCompanyID can leave one behind and a backup has to be able to
	// represent what a store holds — so refusing it here is what keeps one from
	// being created in the first place.
	if deltas.EqualFiles(latestVersionInfo) && companyID == latestVersionInfo.CompanyID {
		return docdb.ErrNoChanges
	}

	// Copy the previous version into a local before taking its address, rather
	// than aliasing the fetched struct's field into the new version's metadata.
	prevVersion := latestVersionInfo.Version
	newVersionInfo, err := c.metadataStore.CreateDocumentVersion(ctx, CreateDocumentVersionInput{
		DocID:           docID,
		CompanyID:       companyID,
		UserID:          userID,
		Reason:          reason,
		NewVersion:      result.Version,
		PreviousVersion: &prevVersion,
		AddedFiles:      fileInfosNamed(resultingFiles, deltas.AddedFiles),
		ModifiedFiles:   fileInfosNamed(resultingFiles, deltas.ModifiedFiles),
		RemovedFiles:    deltas.RemovedFiles,
		Files:           resultingFiles,
	})
	if err != nil {
		return err
	}

	// rollbackNewVersion removes the metadata version just added plus the file
	// blobs written for it, joining any cleanup error onto cause. Used when a
	// later step fails after the metadata version is already committed, so the
	// store is not left with a version that references missing file content.
	//
	// The blobs to delete are taken from the hash set DeleteDocumentVersion
	// reports as referenced only by the removed version. Deleting the version's
	// addedFiles/modifiedFiles hashes directly would also wipe blobs that share
	// their content hash with a sibling version (content is deduplicated by
	// hash across the whole document) and corrupt those versions.
	rollbackNewVersion := func(cause error) error {
		cleanupCtx, cancelCleanup := rollbackCtx(ctx)
		defer cancelCleanup()
		_, hashesToDelete, pgErr := c.metadataStore.DeleteDocumentVersion(cleanupCtx, docID, result.Version)
		if pgErr != nil {
			// Without the metadata delete the safe hash set is unknown, so do
			// not guess: leaving the blobs is preferable to deleting shared ones.
			return errors.Join(cause, pgErr)
		}
		if len(hashesToDelete) > 0 {
			s3Err := c.documentStore.DeleteDocumentHashes(cleanupCtx, docID, hashesToDelete)
			if s3Err != nil {
				cause = errors.Join(cause, s3Err)
			}
		}
		return cause
	}

	// The metadata version is committed from here on, so every remaining
	// failure has to undo it — including a panic from a store, which reaches
	// this deferred rollback but not a rollback call written at each failure
	// site. errs.RecoverPanicAsError is registered after it so it runs first
	// and turns the panic into the err this keys on, and is deferred directly
	// because recover only recovers when the deferred function calls it itself.
	defer func() {
		if err != nil {
			err = rollbackNewVersion(err)
		}
	}()
	defer errs.RecoverPanicAsError(&err)

	// The added/modified FileInfos were already computed above to build the
	// metadata version, so the hashes returned here are not needed again.
	_, err = c.documentStore.CreateDocumentVersion(ctx, docID, result.Version, writeFiles)
	if err != nil {
		return err
	}

	safeOnNewVersion := func() (err error) {
		defer errs.RecoverPanicAsError(&err)
		return onNewVersion(ctx, newVersionInfo)
	}

	return safeOnNewVersion()
}

func (c *conn) AddMultiDocumentVersion(ctx context.Context, docIDs uu.IDSlice, userID uu.ID, reason string, createVersion docdb.CreateVersionFunc, onNewVersion docdb.OnNewVersionFunc) error {
	return docdb.AddMultiDocumentVersionImpl(ctx, c, docIDs, userID, reason, createVersion, onNewVersion)
}

func (c *conn) RestoreDocument(ctx context.Context, doc *docdb.HashedDocument, recreate bool) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, doc, recreate)

	if err = ctx.Err(); err != nil {
		return err
	}
	if err = doc.Validate(); err != nil {
		return err
	}

	docExists, err := c.DocumentExists(ctx, doc.ID)
	if err != nil {
		return err
	}

	if recreate {
		// NOTE: recreate deletes the existing document before the replacement
		// is written and is therefore not atomic — a later failure in this call
		// leaves the document absent (the rollback below only undoes what this
		// call created, not this up-front delete). See Conn.RestoreDocument.
		//
		// The delete is not gated on docExists, which reports only what the
		// DocumentStore holds. The two stores are written independently, so a
		// document can exist as metadata alone: a migration that mirrored the
		// version rows but never copied the file content, or a write cancelled
		// between the two steps. Skipping the delete for such a document left
		// the loop below taking the genesis path for a version the
		// MetadataStore already holds, which the one-genesis-per-document index
		// refuses with ErrDocumentAlreadyExists — so recreate failed on exactly
		// the half-written state it exists to repair, and CreateDocument's
		// rollback deliberately keeps the blobs it wrote for that error,
		// leaving them behind too.
		//
		// DeleteDocument reports not-found only when neither store holds
		// anything, which is not a failure for a restore that is about to write
		// the document from scratch.
		delErr := c.DeleteDocument(ctx, doc.ID)
		if delErr != nil && !errors.Is(delErr, os.ErrNotExist) {
			return delErr
		}
		docExists = false
	}

	versionTimes := doc.VersionTimes()

	var (
		// metadataVersions are the versions the MetadataStore already holds.
		// They are queried even when the DocumentStore holds nothing for the
		// document, because the two stores can be populated independently: a
		// copy into a fresh DocumentStore that reuses a MetadataStore already
		// holding every version of the document must not mistake those versions
		// for ones it created, nor try to create them a second time.
		metadataVersions []docdb.VersionTime
		// skipVersions are the versions this call has nothing left to do for:
		// stored in the MetadataStore and with every file present in the
		// DocumentStore. A version in metadataVersions but not in skipVersions
		// still needs its files written.
		skipVersions []docdb.VersionTime
		// storedFiles are the (name, content hash) pairs the DocumentStore is
		// known to hold, so they are not written again. It starts from what the
		// presence check found and grows with every file written below: a file
		// carried forward unchanged is the same content-addressed object in
		// every version that references it, so writing it once is enough.
		storedFiles map[docdb.FileInfo]bool
	)
	if !recreate {
		versions, versionsErr := c.DocumentVersions(ctx, doc.ID)
		switch {
		case versionsErr == nil:
			metadataVersions = versions
		case errors.As(versionsErr, &docdb.ErrDocumentNotFound{}):
			// The MetadataStore does not know the document: every version of
			// the backup has to be created.
		default:
			return versionsErr
		}

		// Company ownership is the MetadataStore's, so the mismatch check is
		// gated on that store knowing the document rather than on the
		// DocumentStore holding blobs for it.
		//
		// The stored company is compared against the company the backup names
		// for the latest stored version, not against the backup's current
		// company, so a backup whose newer versions move the document to
		// another company restores that move instead of being refused as a
		// mismatch.
		if len(metadataVersions) > 0 {
			currCompanyID, companyErr := c.DocumentCompanyID(ctx, doc.ID)
			if companyErr != nil {
				return companyErr
			}
			if companyErr = docdb.CheckRestoreCompanyID(doc, metadataVersions, currCompanyID); companyErr != nil {
				return companyErr
			}
		}

		// With no object at all under the document, no version can be fully
		// stored, so the per-file check is not worth a round trip — and every
		// file written below is then absent for that reason instead, which is
		// what the rollback's delete of the written hashes rests on. A recreate
		// deleted the document above and is in the same position.
		if docExists {
			skipVersions, storedFiles, err = c.versionsFullyStored(ctx, doc, versionTimes, metadataVersions)
			if err != nil {
				return err
			}
		}
	}
	if storedFiles == nil {
		storedFiles = make(map[docdb.FileInfo]bool)
	}

	noopOnNew := func(context.Context, *docdb.VersionInfo) error { return nil }

	// Roll back what this call created if a later step fails, so a partial
	// restore does not leave a half-written document behind. If the document was
	// created fresh here, drop it entirely; otherwise remove only the versions
	// added here, leaving pre-existing ones intact.
	var (
		createdVersions []docdb.VersionTime
		createdDoc      bool
		// writtenFiles are the files this call uploads to the DocumentStore, by
		// name and content hash, recorded before each write so a write that
		// fails partway is cleaned up too.
		//
		// Deleting the versions is not enough to undo the file writes. A
		// version whose metadata was already stored is not this call's to
		// remove and never enters createdVersions — which is the whole of a
		// restore into a MetadataStore in versions-exist mode — so without this
		// every object uploaded before the failure stayed behind orphaned.
		//
		// Recorded by name and hash rather than by hash alone, because a hash
		// does not identify one object: a document can hold the same content
		// under two filenames, and a hash-only delete would remove the object
		// this call never wrote, corrupting a version the restore was not
		// touching. Size is deliberately left zero — only Name and Hash address
		// a file in a DocumentStore, the same convention versionsFullyStored
		// uses for its keys.
		//
		// Deleting exactly these is safe because every one of them was written
		// for a file the DocumentStore was asked about and reported absent
		// under that name (see versionsFullyStored), or for a document it held
		// nothing for at all: removing it restores exactly the state the call
		// found.
		writtenFiles []docdb.FileInfo
	)
	defer func() {
		if err == nil {
			return
		}
		cleanupCtx, cancelCleanup := rollbackCtx(ctx)
		defer cancelCleanup()
		if createdDoc {
			err = errors.Join(err, c.DeleteDocument(cleanupCtx, doc.ID))
			return
		}
		// Only the metadata rows are removed here, through the MetadataStore
		// rather than through the composite DeleteDocumentVersion. That one
		// also deletes the content hashes the removed version alone referenced,
		// and a version this call created can reference content it did not
		// write: files the DocumentStore already held, which is exactly why
		// nothing was uploaded for it. The content this call is answerable for
		// is writtenFiles, and nothing else may be deleted.
		metadataRolledBack := true
		for i := len(createdVersions) - 1; i >= 0; i-- {
			_, _, delErr := c.metadataStore.DeleteDocumentVersion(cleanupCtx, doc.ID, createdVersions[i])
			if delErr != nil {
				metadataRolledBack = false
				err = errors.Join(err, delErr)
			}
		}
		if !metadataRolledBack {
			// A version whose metadata delete failed — the MetadataStore went
			// away mid-cleanup, say — is still committed and still names its
			// files. Deleting those files now would leave a version pointing at
			// content that is gone, which no reader can tell apart from
			// corruption and no later restore detects as missing metadata.
			// Orphaned objects are the lesser failure: they cost storage, they
			// are found by the presence check of the next restore, and they are
			// overwritten by content-addressed writes of the same bytes.
			return
		}
		if len(writtenFiles) > 0 {
			// Files already removed with their version are silently ignored by
			// DeleteDocumentHashFiles, and a not-found document means the
			// deletes above removed the last of it.
			delErr := c.documentStore.DeleteDocumentHashFiles(cleanupCtx, doc.ID, writtenFiles)
			if delErr != nil && !errors.Is(delErr, os.ErrNotExist) {
				err = errors.Join(err, delErr)
			}
		}
	}()
	// Turn a panic from a store into the error the rollback above keys on:
	// registered after it so it runs first, and deferred directly because
	// recover only recovers when the deferred function calls it itself. The
	// func params are already added by the WrapWithFuncParams above.
	defer errs.RecoverPanicAsError(&err)

	for i, v := range versionTimes {
		if !recreate && versionTimeIn(skipVersions, v) {
			continue
		}
		hv := doc.Versions[v]
		files := hashedVersionFilesMissingFrom(doc, hv, storedFiles)
		versionInMetadata := versionTimeIn(metadataVersions, v)

		// CreateDocument writes a document's genesis version and enforces that
		// the document does not exist yet, so it only applies while neither
		// store knows anything about this version. A MetadataStore that already
		// holds the version would refuse the insert as a duplicate, which is
		// precisely what the merge path below expects and handles, so such a
		// version goes there even when the DocumentStore is still empty.
		if !docExists && !versionInMetadata {
			// Created with the company of the genesis version, not the
			// document's current one: a document moved between companies keeps
			// the company of every version it was committed under, and the
			// versions restored after this one carry the move forward.
			writtenFiles = appendWrittenFiles(writtenFiles, files, hv)
			err = c.CreateDocument(ctx, doc.VersionCompanyID(v), doc.ID, hv.CommitUserID, hv.CommitReason, v, files, noopOnNew)
			if err != nil {
				return err
			}
			docExists = true
			// Only a document that neither store knew may be dropped whole by
			// the rollback. If the MetadataStore already held versions of it,
			// they are not this call's to delete, so the genesis version is
			// rolled back individually like every other version created here.
			if len(metadataVersions) == 0 {
				createdDoc = true
			} else {
				createdVersions = append(createdVersions, v)
			}
			markVersionFilesStored(hv, storedFiles)
			continue
		}

		// Merge-restore: diff against the backup's predecessor rather than
		// the DB's latest, so middle versions don't trip AddDocumentVersion's
		// strictly-after ordering check. Call metadataStore directly because
		// (*conn).AddDocumentVersion enforces newVersion > latestOnDisk.
		//
		// The whole VersionInfo is derived by HashedDocument.VersionInfo, so
		// this restore path can't drift from the derivation of the Conn the
		// document was backed up from, which would fail the comparison of a
		// MetadataStore in versions-exist mode. It cannot fail for a document
		// that passed doc.Validate() above: v comes from doc.VersionTimes(),
		// and Validate rejects a file hash missing from HashedFiles.
		//
		// vi.PrevVersion is nil for the earliest restored version: it has no
		// predecessor, so prev_version is stored as NULL. Passing a pointer to
		// the zero VersionTime here would fail VersionTime.Value(). vi.Files is
		// the version's complete file set, passed as Files so the store stores
		// it directly without looking the predecessor up to re-derive the
		// carry-forward set.
		//
		// RelinkSuccessor names the backup's own next version, because this is a
		// version of a backup being filled into whatever chain is on disk, not
		// an append: restoring a version that was deleted from the middle has
		// to take back the successor DeleteDocumentVersion relinked to its
		// predecessor. Naming it is what keeps a version this restore must not
		// touch from being adopted instead — a concurrent append, or a version
		// the destination has and the backup does not, either of which can
		// chain off the same predecessor and sort after v. Versions on disk
		// that are not in doc.Versions are kept as-is (see Conn.RestoreDocument),
		// and the backup's next version is the only row that may move. The last
		// version of the backup has no successor to take back and names none.
		// See CreateDocumentVersionInput.RelinkSuccessor.
		var relinkSuccessor *docdb.VersionTime
		if i+1 < len(versionTimes) {
			relinkSuccessor = &versionTimes[i+1]
		}

		var vi *docdb.VersionInfo
		vi, err = doc.VersionInfo(v)
		if err != nil {
			return err
		}
		_, err = c.metadataStore.CreateDocumentVersion(ctx, CreateDocumentVersionInput{
			DocID:           vi.DocID,
			CompanyID:       vi.CompanyID,
			UserID:          vi.CommitUserID,
			Reason:          vi.CommitReason,
			NewVersion:      vi.Version,
			PreviousVersion: vi.PrevVersion,
			AddedFiles:      fileInfosNamed(vi.Files, vi.AddedFiles),
			ModifiedFiles:   fileInfosNamed(vi.Files, vi.ModifiedFiles),
			RemovedFiles:    vi.RemovedFiles,
			Files:           vi.Files,
			RelinkSuccessor: relinkSuccessor,
		})
		switch {
		case err == nil:
			// Record as created right after the metadata commit so the rollback
			// also covers a failure of the following blob write — but only for a
			// version this call added to the MetadataStore. A version that was
			// already stored (a store in versions-exist mode verifies it and
			// inserts nothing) is not this call's to remove.
			if !versionInMetadata {
				createdVersions = append(createdVersions, v)
			}
		case versionInMetadata && isAlreadyExistsErr(err):
			// The version reached this point because its files are missing from
			// the DocumentStore, not because its metadata is missing. A store
			// that really inserts rejects the duplicate; that rejection is the
			// expected answer here, so continue and write the missing files.
			// The metadata row is not this call's, so it stays out of the
			// rollback and is left untouched by it.
			//
			// The rejected input was never stored, so verify that the version
			// already there is the one whose files are about to be written.
			err = c.assertStoredFilesMatch(ctx, vi)
			if err != nil {
				return err
			}
		default:
			return err
		}
		// The metadata version was already written above, so the FileInfos
		// returned by the blob write are not needed here. Only the files the
		// DocumentStore does not already hold are written: a version reached
		// here because some of its content is missing, not necessarily all of
		// it, and re-writing what is there costs a full upload of the whole
		// version to repair one absent object. Nothing is written at all for a
		// version whose files all turned out to be present, which happens when
		// the MetadataStore did not know it.
		if len(files) > 0 {
			writtenFiles = appendWrittenFiles(writtenFiles, files, hv)
			_, err = c.documentStore.CreateDocumentVersion(ctx, doc.ID, v, files)
			if err != nil {
				return err
			}
			markVersionFilesStored(hv, storedFiles)
		}
		// The DocumentStore now holds objects for the document, so a following
		// version that neither store knows must not take the genesis path.
		docExists = true
	}
	return nil
}

// assertStoredFilesMatch verifies that the version already stored in the
// MetadataStore has the same file set as want, the version a restore is about
// to write the files of.
//
// Only the file set is compared. The store rejected want as a duplicate, so
// nothing else about want was persisted or can conflict with what is stored;
// the file set is what decides whether the blobs about to be written are the
// ones that version references. Comparing the rest would also be wrong at this
// layer: a MetadataStore may normalize fields it stores — pgstore normalizes
// the commit user ID — which only it can account for.
func (c *conn) assertStoredFilesMatch(ctx context.Context, want *docdb.VersionInfo) error {
	stored, err := c.metadataStore.DocumentVersionInfo(ctx, want.DocID, want.Version)
	if err != nil {
		return errs.Errorf(
			"assumed document %s version %s to exist in the MetadataStore: %w",
			want.DocID, want.Version, err,
		)
	}
	if !stored.EqualFiles(want) {
		return errs.Errorf(
			"cannot restore document %s version %s: the stored version has a different file set than the backup:\n\tstored: %v\n\tbackup: %v",
			want.DocID, want.Version, stored.Files, want.Files,
		)
	}
	return nil
}

// rollbackTimeout bounds a rollback that outlives the context of the call it
// undoes. It is generous because a rollback deletes a whole document's objects
// in paginated batches and giving up halfway leaves exactly the partial state
// it is there to remove, but it must stay finite so a cancelled or timed-out
// caller — an HTTP handler, a shutting-down worker — is not held indefinitely.
const rollbackTimeout = time.Minute

// rollbackCtx returns the context to roll a failed write back with, and the
// cancel func the caller must defer.
//
// Cancellation is precisely the case that leaves a half-written document
// behind, and rolling back with the same cancelled context would fail every
// delete, so the partial state would survive: a committed metadata version
// whose file content was never written — exactly the state versionsFullyStored
// has to detect and RestoreDocument to repair. WithoutCancel keeps the context
// values, so the rollback still runs against the same transaction and store
// configuration, and the fresh deadline keeps it bounded.
func rollbackCtx(ctx context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.WithoutCancel(ctx), rollbackTimeout)
}

// isAlreadyExistsErr reports whether err says that what was to be inserted is
// already stored. A duplicate genesis version is reported as an existing
// document, any later duplicate as an existing version.
func isAlreadyExistsErr(err error) bool {
	return errors.As(err, &docdb.ErrVersionAlreadyExists{}) ||
		errors.As(err, &docdb.ErrDocumentAlreadyExists{})
}

// versionsFullyStored returns the versions of doc that a merge-restore has
// nothing left to do for: held by the MetadataStore and with every file present
// in the DocumentStore. It also returns the files it found present, so a
// version that is only partly stored writes what is missing instead of every
// file it has: the per-file answer is what the check is made of, and throwing
// it away would re-upload whole versions to repair one absent object.
//
// Presence in the MetadataStore alone does not mean a version was copied. The
// two stores are not necessarily populated together: a copy into a fresh
// DocumentStore that reuses a MetadataStore already holding every version of
// the document (see pgstore.ContextWithMetadataStoreVersionsExist) would
// otherwise skip every version — including the ones whose files were never
// written, when an earlier run was interrupted after writing some — and report
// success for a document whose files are missing.
//
// A DocumentStore does not track versions, only files addressed by name and
// content hash, so a version counts as stored exactly when all of its files
// are. Every file is checked in a single DocumentStore call, so the common case
// of a document that is fully present costs one round trip rather than one per
// version or per file.
//
// The presence check covers the files of every version of the backup, not only
// of the versions that can be skipped. Only a version the MetadataStore already
// holds can be skipped, but the answer for the other versions' files is what
// makes every file this restore writes a file the store was asked about and
// reported absent — which is what lets the rollback delete those objects
// without having to reason about whether they were already there.
func (c *conn) versionsFullyStored(ctx context.Context, doc *docdb.HashedDocument, versionTimes, metadataVersions []docdb.VersionTime) ([]docdb.VersionTime, map[docdb.FileInfo]bool, error) {
	// Collect the distinct files of all versions. Only Name and Hash identify a
	// file in the DocumentStore, so a zero Size makes the FileInfo usable as the
	// deduplicating map key.
	var (
		files []docdb.FileInfo
		asked = make(map[docdb.FileInfo]bool)
	)
	for _, v := range versionTimes {
		for filename, hash := range doc.Versions[v].FileHashes {
			file := docdb.FileInfo{Name: filename, Hash: hash}
			if !asked[file] {
				asked[file] = true
				files = append(files, file)
			}
		}
	}
	exist, err := c.documentStore.DocumentHashFilesExist(ctx, doc.ID, files)
	if err != nil {
		return nil, nil, err
	}

	// present keeps only the files that are there, so the restore can skip
	// writing them again instead of asking a second time.
	present := make(map[docdb.FileInfo]bool, len(files))
	for file, ok := range exist {
		if ok {
			present[file] = true
		}
	}

	// Only a version the MetadataStore holds can be skipped: for one it does not
	// hold, the present files are merely files that need no second write, while
	// the version itself still has to be created.
	var stored []docdb.VersionTime
	for _, v := range versionTimes {
		if !versionTimeIn(metadataVersions, v) {
			continue
		}
		fullyStored := true
		for filename, hash := range doc.Versions[v].FileHashes {
			if !present[docdb.FileInfo{Name: filename, Hash: hash}] {
				fullyStored = false
				break
			}
		}
		if fullyStored {
			stored = append(stored, v)
		}
	}
	return stored, present, nil
}

// fileInfosNamed returns the FileInfos of the passed filenames in that order,
// or nil if no filename was passed. It turns the filename change lists of
// docdb.VersionInfo.SetFileDeltas back into the FileInfos that
// CreateDocumentVersionInput expects.
func fileInfosNamed(files map[string]docdb.FileInfo, filenames []string) []*docdb.FileInfo {
	if len(filenames) == 0 {
		return nil
	}
	infos := make([]*docdb.FileInfo, len(filenames))
	for i, filename := range filenames {
		info := files[filename]
		infos[i] = &info
	}
	return infos
}

// hashedVersionFilesMissingFrom materializes the files of a docdb.HashedVersion
// as in-memory fs.FileReaders backed by the corresponding HashedFiles entries,
// skipping the ones stored already holds.
//
// A DocumentStore addresses a file by name and content hash, so a file it
// already holds under both is the object a write would produce and writing it
// again only costs the upload. Pass a nil or empty stored to get every file.
func hashedVersionFilesMissingFrom(doc *docdb.HashedDocument, hv *docdb.HashedVersion, stored map[docdb.FileInfo]bool) []fs.FileReader {
	files := make([]fs.FileReader, 0, len(hv.FileHashes))
	for filename, hash := range hv.FileHashes {
		if stored[docdb.FileInfo{Name: filename, Hash: hash}] {
			continue
		}
		files = append(files, fs.NewMemFile(filename, doc.HashedFiles[hash]))
	}
	return files
}

// appendWrittenFiles records the files of hv that are about to be uploaded, by
// name and content hash, so a rollback can delete exactly those objects and no
// others. Size is left zero: only Name and Hash address a file in a
// DocumentStore.
//
// The files are the fs.FileReaders a restore is about to write, which carry
// their name but not the hash the DocumentStore addresses them by; hv is the
// version they were materialized from, so its FileHashes is where that hash is.
// A file hv does not name contributes nothing rather than an empty hash: it
// cannot happen for a file this package materialized, and a bogus entry in the
// rollback's delete list is worse than a missing one.
func appendWrittenFiles(written []docdb.FileInfo, files []fs.FileReader, hv *docdb.HashedVersion) []docdb.FileInfo {
	for _, file := range files {
		if hash, ok := hv.FileHashes[file.Name()]; ok {
			written = append(written, docdb.FileInfo{Name: file.Name(), Hash: hash})
		}
	}
	return written
}

// markVersionFilesStored records every file of hv as held by the DocumentStore,
// so a later version carrying one of them forward unchanged does not write the
// same content-addressed object again.
func markVersionFilesStored(hv *docdb.HashedVersion, stored map[docdb.FileInfo]bool) {
	for filename, hash := range hv.FileHashes {
		stored[docdb.FileInfo{Name: filename, Hash: hash}] = true
	}
}

// versionTimeIn reports whether v is one of versions.
//
// TODO: this is a linear scan used for set membership, and RestoreDocument runs
// three of them per version — skipVersions and metadataVersions in its loop,
// plus metadataVersions again inside versionsFullyStored. That is quadratic in
// the number of versions of a document: restoring one with 2000 versions costs
// about 12 million VersionTime.Equal calls, for every document of a company-wide
// migration. Building a map[docdb.VersionTime]bool for each of the two slices
// once, before the loop, gives the same answers in a single pass. Left as is
// here because the correctness fixes of this release should not also restructure
// the restore loop; the slices are what MetadataStore.DocumentVersions returns
// and what the rollback needs in order.
func versionTimeIn(versions []docdb.VersionTime, v docdb.VersionTime) bool {
	for _, e := range versions {
		if e.Equal(v) {
			return true
		}
	}
	return false
}

func safelyCallCreateVersionFunc(
	ctx context.Context,
	docID uu.ID,
	prevVersion docdb.VersionTime,
	prevFiles docdb.FileProvider,
	createVersion docdb.CreateVersionFunc,
) (result *docdb.CreateVersionResult, err error) {
	defer errs.RecoverPanicAsError(&err)

	return createVersion(ctx, docID, prevVersion, prevFiles)
}
