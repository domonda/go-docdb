package docdb

import (
	"context"
	"errors"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

func NewConn(
	documentStore DocumentStore,
	metadataStore MetadataStore,
) Conn {
	return &conn{
		documentStore: documentStore,
		metadataStore: metadataStore,
	}
}

// Callbacks
type (
	// CreateVersionFunc is a callback function used to create a new document version
	// based on the previous version.
	//
	// It receives the previous version timestamp and a FileProvider for accessing
	// the files from the previous version.
	//
	// It should return:
	//   - version: timestamp of the new version wich must be after prevVersion
	//   - writeFiles: Files to write or overwrite in the new version
	//   - removeFiles: Filenames to remove from the previous version
	//   - newCompanyID: Optional new company ID to assign to the document (nil to keep current)
	//   - err: An error if version creation should be aborted
	//
	// If this function returns an error or panics, the entire version creation
	// is atomically rolled back.
	CreateVersionFunc func(ctx context.Context, prevVersion VersionTime, prevFiles FileProvider) (version VersionTime, writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error)

	// OnNewVersionFunc is a callback function invoked after a new document version
	// has been created but before it is committed.
	//
	// It receives the VersionInfo for the newly created version and can perform
	// validation or side effects.
	//
	// If this function returns an error or panics, the entire document/version creation
	// is atomically rolled back, preventing the new version from being committed.
	// This allows the callback to act as a validation gate or to ensure related
	// operations complete successfully before committing the new version.
	OnNewVersionFunc func(ctx context.Context, versionInfo *VersionInfo) error
)

// Conn is an interface for a docdb connection.
type Conn interface {
	// DocumentExists returns true if a document with the passed docID exists in
	DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error)

	// EnumDocumentIDs calls the passed callback with the ID of every document in the database
	EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error

	// EnumCompanyDocumentIDs calls the passed callback with the ID of every document of a company in the database
	EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error

	// DocumentCompanyID returns the companyID for a docID
	DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error)

	// SetDocumentCompanyID changes the companyID for a document
	SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error

	// DocumentVersions returns all version timestamps of a document in ascending order.
	// Returns nil and no error if the document does not exist or has no versions.
	DocumentVersions(ctx context.Context, docID uu.ID) ([]VersionTime, error)

	// LatestDocumentVersion returns the lates VersionTime of a document
	LatestDocumentVersion(ctx context.Context, docID uu.ID) (VersionTime, error)

	// DocumentVersionInfo returns the VersionInfo for a VersionTime
	DocumentVersionInfo(ctx context.Context, docID uu.ID, version VersionTime) (*VersionInfo, error)

	// LatestDocumentVersionInfo returns the VersionInfo for the latest document version
	LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*VersionInfo, error)

	// DocumentVersionFileProvider returns a FileProvider for the files of a document version
	DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version VersionTime) (FileProvider, error)

	// ReadDocumentVersionFile returns the contents of a file of a document version.
	// Wrapped ErrDocumentNotFound, ErrDocumentVersionNotFound, ErrDocumentFileNotFound
	// will be returned in case of such error conditions.
	ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version VersionTime, filename string) (data []byte, err error)

	// DeleteDocument deletes all versions of a document
	// including its workspace directory if checked out.
	DeleteDocument(ctx context.Context, docID uu.ID) error

	// DeleteDocumentVersion deletes a version of a document that must not be checked out
	// and returns the left over versions.
	// If the version is the only version of the document,
	// then the document will be deleted and no leftVersions are returned.
	// Returns wrapped ErrDocumentNotFound, ErrDocumentVersionNotFound, ErrDocumentCheckedOut
	// in case of such error conditions.
	// DeleteDocumentVersion should not be used for normal docdb operations,
	// just to clean up mistakes or sync database states.
	DeleteDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) (leftVersions []VersionTime, err error)

	// CreateDocument creates a new document with the provided files.
	// The document is created with companyID, docID, and userID as metadata,
	// and reason describes why the document is being created.
	//
	// The passed version time is the timestamp of the new version.
	//
	// After the document version is created but before it is committed,
	// the onNewVersion callback is called with the resulting VersionInfo.
	// If onNewVersion returns an error or panics, the entire document creation
	// is atomically rolled back, the error is returned, or the panic is propagated.
	// onNewVersion must not be nil.
	//
	// Returns ErrDocumentAlreadyExists if a document with docID already exists.
	CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, version VersionTime, files []fs.FileReader, onNewVersion OnNewVersionFunc) error

	// AddDocumentVersion adds a new version to an existing document.
	// The createVersion callback is invoked with the previous version info
	// and should return the files to write, files to remove, and optionally
	// a changed company ID for the document (nil to keep current).
	//
	// After the new version is created but before it is committed,
	// the onNewVersion callback is called with the resulting VersionInfo.
	// If createVersion or onNewVersion returns an error or panics,
	// the entire version creation is atomically rolled back,
	// the error is returned, or the panic is propagated.
	// createVersion and onNewVersion must not be nil.
	//
	// Returns wrapped ErrDocumentNotFound if the document does not exist.
	// Returns wrapped ErrNoChanges if the new version has identical files
	// compared to the previous version.
	AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) error

	// RestoreDocument
	RestoreDocument(ctx context.Context, doc *HashedDocument, merge bool) error
}

// DeprecatedConn has check-out, check-in and checkout directory methods.
// It is deprecated and will be removed in the future.
// Use the Conn interface instead.
type DeprecatedConn interface {
	Conn

	// DocumentCheckOutStatus returns the CheckOutStatus of a document.
	// If the document is not checked out, then a nil CheckOutStatus will be returned.
	// The methods Valid() and String() can be called on a nil CheckOutStatus.
	// ErrDocumentNotFound is returned if the document does not exist.
	DocumentCheckOutStatus(ctx context.Context, docID uu.ID) (*CheckOutStatus, error)

	// CheckedOutDocuments returns the CheckOutStatus of all checked out documents.
	CheckedOutDocuments(ctx context.Context) ([]*CheckOutStatus, error)

	// CheckOutNewDocument creates a new document for a company in checked out state.
	CheckOutNewDocument(ctx context.Context, docID, companyID, userID uu.ID, reason string) (status *CheckOutStatus, err error)

	// CheckOutDocument checks out a document for a user with a stated reason.
	// Returns ErrDocumentCheckedOut if the document is already checked out.
	CheckOutDocument(ctx context.Context, docID, userID uu.ID, reason string) (*CheckOutStatus, error)

	// CancelCheckOutDocument cancels a potential checkout.
	// No error is returned if the document was not checked out.
	// If the checkout was created by CheckOutNewDocument,
	// then the new document is deleted without leaving any history
	// and the returned lastVersion.IsNull() is true.
	CancelCheckOutDocument(ctx context.Context, docID uu.ID) (wasCheckedOut bool, lastVersion VersionTime, err error)

	// CheckInDocument checks in a checked out document
	// and returns the VersionInfo for the newly created version.
	CheckInDocument(ctx context.Context, docID uu.ID) (*VersionInfo, error)

	// CheckedOutDocumentDir returns a fs.File for the directory
	// where a document would be checked out.
	CheckedOutDocumentDir(docID uu.ID) fs.File
}

// type DebugFileAccessConn interface {
// 	Conn

// 	DebugGetDocumentDir(docID uu.ID) fs.File
// 	DebugGetDocumentVersionFile(docID uu.ID, version VersionTime, filename string) (fs.File, error)
// }

type conn struct {
	documentStore DocumentStore
	metadataStore MetadataStore
}

func (c *conn) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	return c.documentStore.DocumentExists(ctx, docID)
}

func (c *conn) EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error {
	return c.documentStore.EnumDocumentIDs(ctx, callback)
}

func (c *conn) DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version VersionTime) (FileProvider, error) {
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

func (c *conn) ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version VersionTime, filename string) (data []byte, err error) {
	versionInfo, err := c.metadataStore.DocumentVersionInfo(ctx, docID, version)
	if err != nil {
		return nil, err
	}

	hash := ""
	for _, item := range versionInfo.Files {
		if item.Name == filename {
			hash = item.Hash
			break
		}
	}

	return c.documentStore.ReadDocumentHashFile(ctx, docID, filename, hash)
}

func (c *conn) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	return c.metadataStore.DocumentCompanyID(ctx, docID)
}

func (c *conn) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error {
	return c.metadataStore.SetDocumentCompanyID(ctx, docID, companyID)
}

func (c *conn) DocumentVersions(ctx context.Context, docID uu.ID) ([]VersionTime, error) {
	return c.metadataStore.DocumentVersions(ctx, docID)
}

func (c *conn) LatestDocumentVersion(ctx context.Context, docID uu.ID) (VersionTime, error) {
	return c.metadataStore.LatestDocumentVersion(ctx, docID)
}

func (c *conn) EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error {
	return c.metadataStore.EnumCompanyDocumentIDs(ctx, companyID, callback)
}

func (c *conn) DocumentVersionInfo(ctx context.Context, docID uu.ID, version VersionTime) (*VersionInfo, error) {
	return c.metadataStore.DocumentVersionInfo(ctx, docID, version)
}

func (c *conn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*VersionInfo, error) {
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

func (c *conn) DeleteDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) (leftVersions []VersionTime, err error) {
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
	version VersionTime,
	files []fs.FileReader,
	onNewVersion OnNewVersionFunc,
) error {
	return c.createDocumentVersion(ctx, companyID, docID, userID, reason, version, files, onNewVersion)
}

func (c *conn) createDocumentVersion(
	ctx context.Context,
	companyID,
	docID,
	userID uu.ID,
	reason string,
	version VersionTime,
	files []fs.FileReader,
	onNewVersion OnNewVersionFunc,
) (err error) {
	if version.IsNull() {
		return errs.New("null version passed to createDocumentVersion")
	}
	if onNewVersion == nil {
		return errs.New("nil onNewVersion func passed to createDocumentVersion")
	}

	var versionInfo *VersionInfo

	defer func() {
		errs.RecoverPanicAsErrorWithFuncParams(&err, ctx, companyID, docID, userID, reason, version, files, onNewVersion)
		if err != nil {
			if versionInfo != nil {
				hashes := []string{}
				for _, item := range versionInfo.Files {
					hashes = append(hashes, item.Hash)
				}
				err = errors.Join(c.documentStore.DeleteDocumentHashes(ctx, docID, hashes))
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
	createVersion CreateVersionFunc,
	onNewVersion OnNewVersionFunc,
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

	companyID := latestVersionInfo.CompanyID
	newVersion, writeFiles, removeFiles, newCompanyID, err := safelyCallCreateVersionFunc(
		ctx,
		latestVersionInfo.Version,
		fileProvider,
		createVersion,
	)
	if err != nil {
		return err
	}
	if newVersion.IsNull() {
		return errs.New("version returned from CreateVersionFunc is null")
	}
	if !newVersion.After(latestVersionInfo.Version) {
		return errs.Errorf("version %s returned from CreateVersionFunc is not after previous version %s", newVersion, latestVersionInfo.Version)
	}

	if newCompanyID != nil {
		companyID = *newCompanyID
	}

	addedFiles := []*FileInfo{}
	modifiedFiles := []*FileInfo{}

	for _, file := range writeFiles {
		data, err := file.ReadAll()
		if err != nil {
			return err
		}

		fileInfo := &FileInfo{Name: file.Name(), Size: file.Size(), Hash: ContentHash(data)}
		if fileExists, _ := fileProvider.HasFile(file.Name()); fileExists {
			modifiedFiles = append(modifiedFiles, fileInfo)
		} else {
			addedFiles = append(addedFiles, fileInfo)
		}
	}

	newVersionInfo, err := c.metadataStore.AddDocumentVersion(
		ctx,
		newVersion,
		latestVersionInfo.Version,
		docID,
		companyID,
		userID,
		reason,
		addedFiles,
		modifiedFiles,
		removeFiles,
	)

	if err != nil {
		return err
	}

	if err := c.documentStore.CreateDocument(ctx, docID, newVersion, writeFiles); err != nil {
		return err
	}

	safeOnNewVersion := func() (err error) {
		defer errs.RecoverPanicAsError(&err)
		return onNewVersion(ctx, newVersionInfo)
	}

	err = safeOnNewVersion()
	if err == nil {
		return nil
	}

	_, _, pgCleanupErr := c.metadataStore.DeleteDocumentVersion(ctx, docID, newVersion)
	if pgCleanupErr != nil {
		err = errors.Join(err, pgCleanupErr)
	}

	hashesToDelete := []string{}
	for _, f := range addedFiles {
		hashesToDelete = append(hashesToDelete, f.Hash)
	}

	for _, f := range modifiedFiles {
		hashesToDelete = append(hashesToDelete, f.Hash)
	}

	if s3Err := c.documentStore.DeleteDocumentHashes(ctx, docID, hashesToDelete); s3Err != nil {
		err = errors.Join(err, s3Err)
	}

	return err
}

func (c *conn) RestoreDocument(ctx context.Context, doc *HashedDocument, merge bool) error {
	return ErrNotImplemented
}

func safelyCallCreateVersionFunc(
	ctx context.Context,
	prevVersion VersionTime,
	prevFiles FileProvider,
	createVersion CreateVersionFunc,
) (version VersionTime, writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error) {
	defer errs.RecoverPanicAsError(&err)

	return createVersion(ctx, prevVersion, prevFiles)
}
