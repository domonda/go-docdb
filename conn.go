package docdb

import (
	"context"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

// Callbacks
type (
	// CreateVersionFunc is a callback function used to create a new document version
	// based on the previous version.
	//
	// It receives the previous version timestamp and a FileProvider for accessing
	// the files from the previous version.
	//
	// It should return:
	//   - writeFiles: Files to write or overwrite in the new version
	//   - removeFiles: Filenames to remove from the previous version
	//   - newCompanyID: Optional new company ID to assign to the document (nil to keep current)
	//   - err: An error if version creation should be aborted
	//
	// If this function returns an error or panics, the entire version creation
	// is atomically rolled back.
	CreateVersionFunc func(ctx context.Context, prevVersion VersionTime, prevFiles FileProvider) (writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error)

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
	// After the document version is created but before it is committed,
	// the onNewVersion callback is called with the resulting VersionInfo.
	// If onNewVersion returns an error or panics, the entire document creation
	// is atomically rolled back, the error is returned, or the panic is propagated.
	//
	// Returns ErrDocumentAlreadyExists if a document with docID already exists.
	CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, files []fs.FileReader, onNewVersion OnNewVersionFunc) error

	// AddDocumentVersion adds a new version to an existing document.
	// The createVersion callback is invoked with the previous version info
	// and should return the files to write, files to remove, and optionally
	// a new company ID for the document.
	//
	// After the new version is created but before it is committed,
	// the onNewVersion callback is called with the resulting VersionInfo.
	// If createVersion or onNewVersion returns an error or panics,
	// the entire version creation is atomically rolled back,
	// the error is returned, or the panic is propagated.
	//
	// Returns wrapped ErrDocumentNotFound if the document does not exist.
	// Returns wrapped ErrNoChanges if the new version has identical files
	// compared to the previous version.
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
