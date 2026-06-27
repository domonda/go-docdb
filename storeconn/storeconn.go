// Package storeconn provides a docdb.Conn implementation that combines
// a DocumentStore for file content storage with a MetadataStore
// for version metadata.
package storeconn

import (
	"context"
	"errors"
	"maps"
	"os"

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

func (c *conn) EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error {
	return c.documentStore.EnumDocumentIDs(ctx, callback)
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

func (c *conn) EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error {
	return c.metadataStore.EnumCompanyDocumentIDs(ctx, companyID, callback)
}

func (c *conn) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error) {
	return c.metadataStore.DocumentVersionInfo(ctx, docID, version)
}

func (c *conn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*docdb.VersionInfo, error) {
	return c.metadataStore.LatestDocumentVersionInfo(ctx, docID)
}

func (c *conn) DeleteDocument(ctx context.Context, docID uu.ID) error {
	err := c.metadataStore.DeleteDocument(ctx, docID)
	if err != nil {
		return err
	}
	return c.documentStore.DeleteDocument(ctx, docID)
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
	exists, err := c.documentStore.DocumentExists(ctx, docID)
	if err != nil {
		return err
	}
	if exists {
		return docdb.NewErrDocumentAlreadyExists(docID)
	}

	var versionInfo *docdb.VersionInfo

	defer func() {
		errs.RecoverPanicAsErrorWithFuncParams(&err, ctx, companyID, docID, userID, reason, version, files, onNewVersion)
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
		if !errors.As(err, &docdb.ErrDocumentAlreadyExists{}) {
			if delErr := c.documentStore.DeleteDocument(ctx, docID); delErr != nil && !errors.Is(delErr, os.ErrNotExist) {
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
			if _, _, delErr := c.metadataStore.DeleteDocumentVersion(ctx, docID, version); delErr != nil && !errors.Is(delErr, os.ErrNotExist) {
				err = errors.Join(err, delErr)
			}
		}
	}()

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
	if err := result.Validate(); err != nil {
		return err
	}
	if !result.Version.After(latestVersionInfo.Version) {
		return errs.Errorf("version %s returned from CreateVersionFunc is not after previous version %s", result.Version, latestVersionInfo.Version)
	}

	companyID := result.NewCompanyID.GetOr(latestVersionInfo.CompanyID)

	addedFiles := []*docdb.FileInfo{}
	modifiedFiles := []*docdb.FileInfo{}

	for _, file := range result.WriteFiles {
		data, err := file.ReadAll()
		if err != nil {
			return err
		}

		fileInfo := &docdb.FileInfo{Name: file.Name(), Size: file.Size(), Hash: docdb.ContentHash(data)}
		if fileExists, _ := fileProvider.HasFile(file.Name()); fileExists {
			modifiedFiles = append(modifiedFiles, fileInfo)
		} else {
			addedFiles = append(addedFiles, fileInfo)
		}
	}

	// Compute the resulting full file set (previous files, minus the removed
	// ones, with added/modified overlaid) to enforce, before committing
	// anything, that every version contains at least one file: removing all
	// files of a document is not allowed. It is also passed to
	// CreateDocumentVersion as Files so the store does not re-query the
	// predecessor and re-derive the identical set.
	resultingFiles := make(map[string]docdb.FileInfo, len(latestVersionInfo.Files))
	maps.Copy(resultingFiles, latestVersionInfo.Files)
	for _, name := range result.RemoveFiles {
		delete(resultingFiles, name)
	}
	for _, fi := range addedFiles {
		resultingFiles[fi.Name] = *fi
	}
	for _, fi := range modifiedFiles {
		resultingFiles[fi.Name] = *fi
	}
	if len(resultingFiles) == 0 {
		return errs.Errorf("cannot remove all files of document %s: every version must contain at least one file", docID)
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
		AddedFiles:      addedFiles,
		ModifiedFiles:   modifiedFiles,
		RemovedFiles:    result.RemoveFiles,
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
		_, hashesToDelete, pgErr := c.metadataStore.DeleteDocumentVersion(ctx, docID, result.Version)
		if pgErr != nil {
			// Without the metadata delete the safe hash set is unknown, so do
			// not guess: leaving the blobs is preferable to deleting shared ones.
			return errors.Join(cause, pgErr)
		}
		if len(hashesToDelete) > 0 {
			if s3Err := c.documentStore.DeleteDocumentHashes(ctx, docID, hashesToDelete); s3Err != nil {
				cause = errors.Join(cause, s3Err)
			}
		}
		return cause
	}

	// The added/modified FileInfos were already computed above to build the
	// metadata version, so the hashes returned here are not needed again.
	_, err = c.documentStore.CreateDocumentVersion(ctx, docID, result.Version, result.WriteFiles)
	if err != nil {
		return rollbackNewVersion(err)
	}

	safeOnNewVersion := func() (err error) {
		defer errs.RecoverPanicAsError(&err)
		return onNewVersion(ctx, newVersionInfo)
	}

	err = safeOnNewVersion()
	if err != nil {
		return rollbackNewVersion(err)
	}

	return nil
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

	if recreate && docExists {
		// NOTE: recreate deletes the existing document before the replacement
		// is written and is therefore not atomic — a later failure in this call
		// leaves the document absent (the rollback below only undoes what this
		// call created, not this up-front delete). See Conn.RestoreDocument.
		if err = c.DeleteDocument(ctx, doc.ID); err != nil {
			return err
		}
		docExists = false
	}

	var existingVersions []docdb.VersionTime
	if !recreate && docExists {
		currCompanyID, err := c.DocumentCompanyID(ctx, doc.ID)
		if err != nil {
			return err
		}
		if currCompanyID != doc.CompanyID {
			return errs.Errorf(
				"cannot restore document %s into existing document with different companyID: backup %s != on-disk %s",
				doc.ID, doc.CompanyID, currCompanyID,
			)
		}
		existingVersions, err = c.DocumentVersions(ctx, doc.ID)
		if err != nil {
			return err
		}
	}

	noopOnNew := func(context.Context, *docdb.VersionInfo) error { return nil }
	versionTimes := doc.VersionTimes()

	// Roll back versions created during this call if a later step fails, so a
	// partial restore does not leave a half-written document behind. If the
	// document was created fresh here, drop it entirely; otherwise remove only
	// the versions added here, leaving pre-existing ones intact.
	var (
		createdVersions []docdb.VersionTime
		createdDoc      bool
	)
	defer func() {
		if err == nil {
			return
		}
		if createdDoc {
			err = errors.Join(err, c.DeleteDocument(ctx, doc.ID))
			return
		}
		for i := len(createdVersions) - 1; i >= 0; i-- {
			if _, delErr := c.DeleteDocumentVersion(ctx, doc.ID, createdVersions[i]); delErr != nil {
				err = errors.Join(err, delErr)
			}
		}
	}()

	for i, v := range versionTimes {
		if !recreate && versionTimeIn(existingVersions, v) {
			continue
		}
		hv := doc.Versions[v]
		files := hashedVersionFiles(doc, hv)

		if !docExists {
			if err = c.CreateDocument(ctx, doc.CompanyID, doc.ID, hv.CommitUserID, hv.CommitReason, v, files, noopOnNew); err != nil {
				return err
			}
			docExists = true
			createdDoc = true
			continue
		}

		// Merge-restore: diff against the backup's predecessor rather than
		// the DB's latest, so middle versions don't trip AddDocumentVersion's
		// strictly-after ordering check. Call metadataStore directly because
		// (*conn).AddDocumentVersion enforces newVersion > latestOnDisk.
		var (
			previousVersion *docdb.VersionTime
			prevHashes      map[string]string
		)
		if i > 0 {
			prev := versionTimes[i-1]
			previousVersion = &prev
			prevHashes = doc.Versions[prev].FileHashes
		}

		var (
			addedFiles    []*docdb.FileInfo
			modifiedFiles []*docdb.FileInfo
			removedFiles  []string
		)
		// resultingFiles is this version's complete file set (hv.FileHashes is
		// authoritative), passed as Files so the store stores it directly without
		// looking the predecessor up to re-derive the carry-forward set.
		resultingFiles := make(map[string]docdb.FileInfo, len(hv.FileHashes))
		for filename, hash := range hv.FileHashes {
			fi := &docdb.FileInfo{Name: filename, Size: int64(len(doc.HashedFiles[hash])), Hash: hash}
			resultingFiles[filename] = *fi
			if prevHash, ok := prevHashes[filename]; !ok {
				addedFiles = append(addedFiles, fi)
			} else if prevHash != hash {
				modifiedFiles = append(modifiedFiles, fi)
			}
		}
		for prevFilename := range prevHashes {
			if _, ok := hv.FileHashes[prevFilename]; !ok {
				removedFiles = append(removedFiles, prevFilename)
			}
		}

		// previousVersion is nil for the earliest restored version (i == 0): it
		// has no predecessor, so prev_version is stored as NULL. Passing a
		// pointer to the zero VersionTime here would fail VersionTime.Value().
		_, err = c.metadataStore.CreateDocumentVersion(ctx, CreateDocumentVersionInput{
			DocID:           doc.ID,
			CompanyID:       doc.CompanyID,
			UserID:          hv.CommitUserID,
			Reason:          hv.CommitReason,
			NewVersion:      v,
			PreviousVersion: previousVersion,
			AddedFiles:      addedFiles,
			ModifiedFiles:   modifiedFiles,
			RemovedFiles:    removedFiles,
			Files:           resultingFiles,
		})
		if err != nil {
			return err
		}
		// Record as created right after the metadata commit so the rollback
		// also covers a failure of the following blob write.
		createdVersions = append(createdVersions, v)
		// The metadata version was already written above, so the FileInfos
		// returned by the blob write are not needed here.
		if _, err = c.documentStore.CreateDocumentVersion(ctx, doc.ID, v, files); err != nil {
			return err
		}
	}
	return nil
}

// hashedVersionFiles materializes the files of a docdb.HashedVersion as in-memory
// fs.FileReaders backed by the corresponding HashedFiles entries.
func hashedVersionFiles(doc *docdb.HashedDocument, hv *docdb.HashedVersion) []fs.FileReader {
	files := make([]fs.FileReader, 0, len(hv.FileHashes))
	for filename, hash := range hv.FileHashes {
		files = append(files, fs.NewMemFile(filename, doc.HashedFiles[hash]))
	}
	return files
}

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
