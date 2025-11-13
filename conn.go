package docdb

import (
	"context"

	fs "github.com/ungerik/go-fs"

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

type CreateVersionFunc func(ctx context.Context, prevVersion VersionTime, prevFiles FileProvider) (writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error)

type OnNewVersionFunc func(ctx context.Context, versionInfo *VersionInfo) error

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

	CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, files []fs.FileReader) (*VersionInfo, error)

	AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) error

	// RestoreDocument
	RestoreDocument(ctx context.Context, doc *HashedDocument, merge bool) error

	// InsertDocumentVersion inserts a new version for an existing document.
	// Returns wrapped ErrDocumentNotFound, ErrDocumentVersionAlreadyExists
	// in case of such error conditions.
	// InsertDocumentVersion should not be used for normal docdb operations,
	// just to clean up mistakes or sync database states.
	// InsertDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime, userID uu.ID, reason string, files []fs.FileReader) (info *VersionInfo, err error)

	// CreateDocumentVersion creates a new document version.
	//
	// The new version is based on the passed baseVersion
	// which is null (zero value) for a new document.
	// A wrapped ErrVersionNotFound error is returned
	// if the passed non null baseVersion does not exist.
	// A wrapped ErrDocumentAlreadyExists errors is returned
	// in case of a null null baseVersion where a document
	// with the passed docID already exists.
	//
	// If there is already a later version than baseVersion
	// then a wrapped ErrDocumentChanged error is returned.
	//
	// It is valid to change the company a document with a new version
	// by passing a different companyID compared to the baseVersion.
	//
	// It is valid to pass an empty string as reason.
	//
	// The changes for the new version passed as fileChanges
	// map from filenames to content.
	//   - Files with identical names from the base version
	//     will be overwritten with the passed content.
	//   - If a non nil empty slice is passed,
	//     then an empty file will be written.
	//   - If nil is passed as content for a filname,
	//     then the file from the base version will be deleted.
	//     No error is returned if the file to be deleted
	//     does not exist in the base version.
	//
	// If creating the new version was successful so far
	// then the passed onCreate function will be called
	// if it is not nil.
	// The callback is passed the resulting VersionInfo
	// and can prevent the new version from being commited
	// by returning an error.
	//
	// Calling CreateDocumentVersion is atomic per docID
	// meaning that other CreateDocumentVersion calls are blocked
	// until the first call with the same docID retunred.
	//
	// Document IDs are unique accross the whole database
	// so different companies can not have documents with
	// the same ID.
	// CreateDocumentVersion(ctx context.Context, companyID, docID, userID uu.ID, reason string, baseVersion VersionTime, fileChanges map[string][]byte, onCreate OnCreateVersionFunc) (*VersionInfo, error)
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
	files []fs.FileReader,
) (*VersionInfo, error) {
	return c.createDocumentVersion(ctx, companyID, docID, userID, reason, files)
}

func (c *conn) createDocumentVersion(
	ctx context.Context,
	companyID,
	docID,
	userID uu.ID,
	reason string,
	files []fs.FileReader,
) (*VersionInfo, error) {
	if err := c.documentStore.CreateDocument(ctx, docID, files); err != nil {
		return nil, err
	}

	versionInfo, err := c.metadataStore.CreateDocument(ctx, companyID, docID, userID, reason, files)

	if err != nil {
		hashes := []string{}
		for _, item := range versionInfo.Files {
			hashes = append(hashes, item.Hash)
		}
		c.documentStore.DeleteDocumentHashes(ctx, docID, hashes) // #nosec G104
	}

	return versionInfo, err
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

	latestVersionInfo, err := c.metadataStore.LatestDocumentVersionInfo(ctx, docID)
	if err != nil {
		return err
	}

	newVersion := NewVersionTime(ctx)
	if !newVersion.After(latestVersionInfo.Version) {
		return errs.Errorf("new version %s not after previous version %s", newVersion, latestVersionInfo.Version)
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
	writeFiles, removeFiles, newCompanyID, err := safelyCallCreateVersionFunc(
		ctx,
		latestVersionInfo.Version,
		fileProvider,
		createVersion,
	)

	if newCompanyID != nil {
		companyID = *newCompanyID
	}

	if err != nil {
		return err
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

	if err := c.documentStore.CreateDocument(ctx, docID, writeFiles); err != nil {
		return err
	}

	return onNewVersion(ctx, newVersionInfo)

}

func (c *conn) RestoreDocument(ctx context.Context, doc *HashedDocument, merge bool) error {
	return ErrNotImplemented
}

func safelyCallCreateVersionFunc(
	ctx context.Context,
	prevVersion VersionTime,
	prevFiles FileProvider,
	createVersion CreateVersionFunc,
) (writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error) {
	defer errs.RecoverPanicAsError(&err)
	return createVersion(ctx, prevVersion, prevFiles)
}
