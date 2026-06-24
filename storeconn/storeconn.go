// Package storeconn provides a docdb.Conn implementation that combines
// a DocumentStore for file content storage with a MetadataStore
// for version metadata.
package storeconn

import (
	"context"
	"errors"
	"maps"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"

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

	hashes := []string{}
	for _, item := range versionInfo.Files {
		hashes = append(hashes, item.Hash)
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
	if err := c.metadataStore.DeleteDocument(ctx, docID); err != nil {
		return err
	}

	if err := c.documentStore.DeleteDocument(ctx, docID); err != nil {
		return err
	}

	return nil
}

func (c *conn) DeleteDocumentVersion(ctx context.Context, docID uu.ID, version docdb.VersionTime) (leftVersions []docdb.VersionTime, err error) {
	leftVersions, hashesToDelete, err := c.metadataStore.DeleteDocumentVersion(ctx, docID, version)

	if err != nil {
		return nil, err
	}

	if err = c.documentStore.DeleteDocumentHashes(ctx, docID, hashesToDelete); err != nil {
		return nil, err
	}

	return leftVersions, err
}

func (c *conn) CreateDocument(
	ctx context.Context,
	companyID,
	docID,
	userID uu.ID,
	reason string,
	version docdb.VersionTime,
	files []fs.FileReader,
	onNewVersion docdb.OnNewVersionFunc,
) error {
	if len(files) == 0 {
		// The first version of a document must contain at least one file:
		// a document cannot start with an empty, change-less version.
		return errs.Errorf("cannot create document %s without files", docID)
	}
	return c.createDocumentVersion(ctx, companyID, docID, userID, reason, version, files, onNewVersion)
}

func (c *conn) createDocumentVersion(
	ctx context.Context,
	companyID,
	docID,
	userID uu.ID,
	reason string,
	version docdb.VersionTime,
	files []fs.FileReader,
	onNewVersion docdb.OnNewVersionFunc,
) (err error) {
	if err := version.Validate(); err != nil {
		return err
	}
	if onNewVersion == nil {
		return errs.New("nil onNewVersion func passed to createDocumentVersion")
	}

	var versionInfo *docdb.VersionInfo

	defer func() {
		errs.RecoverPanicAsErrorWithFuncParams(&err, ctx, companyID, docID, userID, reason, version, files, onNewVersion)
		if err != nil {
			if versionInfo != nil {
				hashes := []string{}
				for _, item := range versionInfo.Files {
					hashes = append(hashes, item.Hash)
				}
				err = errors.Join(err, c.documentStore.DeleteDocumentHashes(ctx, docID, hashes))
			}
			err = errors.Join(err, c.metadataStore.DeleteDocument(ctx, docID))
		}
	}()

	err = c.documentStore.CreateDocument(ctx, docID, version, files)
	if err != nil {
		return err
	}

	versionInfo, err = c.metadataStore.CreateDocument(ctx, companyID, docID, userID, reason, version, files)
	if err != nil {
		return err
	}

	return onNewVersion(ctx, versionInfo)
}

func (c *conn) AddDocumentVersion(
	ctx context.Context,
	docID,
	userID uu.ID,
	reason string,
	createVersion docdb.CreateVersionFunc,
	onNewVersion docdb.OnNewVersionFunc,
) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, userID, reason, createVersion, onNewVersion)

	for _, check := range []func() error{ctx.Err, docID.Validate, userID.Validate} {
		if err := check(); err != nil {
			return err
		}
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

	hashes := []string{}
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
	// files of a document is not allowed.
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

	newVersionInfo, err := c.metadataStore.AddDocumentVersion(
		ctx,
		result.Version,
		latestVersionInfo.Version,
		docID,
		companyID,
		userID,
		reason,
		addedFiles,
		modifiedFiles,
		result.RemoveFiles,
	)

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

	if err = c.documentStore.CreateDocument(ctx, docID, result.Version, result.WriteFiles); err != nil {
		return rollbackNewVersion(err)
	}

	safeOnNewVersion := func() (err error) {
		defer errs.RecoverPanicAsError(&err)
		return onNewVersion(ctx, newVersionInfo)
	}

	if err = safeOnNewVersion(); err != nil {
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
			prevVersion docdb.VersionTime
			prevHashes  map[string]string
		)
		if i > 0 {
			prevVersion = versionTimes[i-1]
			prevHashes = doc.Versions[prevVersion].FileHashes
		}

		var (
			addedFiles    []*docdb.FileInfo
			modifiedFiles []*docdb.FileInfo
			removedFiles  []string
		)
		for filename, hash := range hv.FileHashes {
			fi := &docdb.FileInfo{Name: filename, Size: int64(len(doc.HashedFiles[hash])), Hash: hash}
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

		if _, err = c.metadataStore.AddDocumentVersion(
			ctx, v, prevVersion, doc.ID, doc.CompanyID, hv.CommitUserID,
			hv.CommitReason, addedFiles, modifiedFiles, removedFiles,
		); err != nil {
			return err
		}
		// Record as created right after the metadata commit so the rollback
		// also covers a failure of the following blob write.
		createdVersions = append(createdVersions, v)
		if err = c.documentStore.CreateDocument(ctx, doc.ID, v, files); err != nil {
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
