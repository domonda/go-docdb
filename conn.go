package docdb

import (
	"context"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

// Conn is an interface for a docdb connection.
type Conn interface {
	// DocumentExists returns true if a document with the passed docID exists
	DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error)

	// CompanyIDs returns the IDs of all companies that have documents in the
	// database, sorted by ID for a consistent order.
	CompanyIDs(ctx context.Context) (uu.IDSlice, error)

	// CompanyDocumentIDs returns the IDs of all documents of a company in the
	// database, sorted by ID for a consistent order.
	//
	// A document is listed under the company of its latest version only. A
	// document moved between companies by a new version that names another
	// company is listed under that company from then on, and no longer under
	// the previous one, even though its earlier versions still name it.
	CompanyDocumentIDs(ctx context.Context, companyID uu.ID) (uu.IDSlice, error)

	// DocumentCompanyID returns the companyID for a docID, which is the company
	// of the document's latest version.
	DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error)

	// SetDocumentCompanyID changes the companyID for a document without
	// committing a version. Prefer moving a document between companies with a
	// new version created by AddDocumentVersion with
	// CreateVersionResult.NewCompanyID, which records the move in the
	// document's history instead of changing its owner behind it.
	SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error

	// DocumentVersions returns all version timestamps of a document in ascending order.
	// Returns ErrDocumentNotFound if the document does not exist.
	DocumentVersions(ctx context.Context, docID uu.ID) ([]VersionTime, error)

	// LatestDocumentVersion returns the latest VersionTime of a document
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

	// DeleteDocument deletes all versions and stored files of a document.
	// Returns wrapped ErrDocumentNotFound in case the document does not exist.
	DeleteDocument(ctx context.Context, docID uu.ID) error

	// DeleteDocumentVersion deletes a version of a document
	// and returns the left over versions.
	// If the version is the only version of the document,
	// then the document will be deleted and no leftVersions are returned.
	// Deleting the latest version of a document that was moved between
	// companies re-assigns the document to the company of the version that
	// becomes the latest one, so it is always owned by and listed under the
	// company of its latest version.
	// Returns wrapped ErrDocumentNotFound and ErrDocumentVersionNotFound
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
	// At least one file must be provided: a document's first version cannot be
	// empty, so an empty files slice is rejected with an error.
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
	// A new version must keep at least one file: removing all files of a
	// document is rejected with an error (use DeleteDocument to remove the
	// document entirely).
	//
	// Returns wrapped ErrDocumentNotFound if the document does not exist.
	// Returns wrapped ErrNoChanges if the new version has identical files
	// compared to the previous version and does not change the company.
	// A version that only changes the company is how a document is moved
	// between companies and is not a change-less version.
	AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) error

	// AddMultiDocumentVersion adds a new version to multiple existing documents as atomic operation.
	// See AddDocumentVersion for details on the callbacks and error handling.
	// Documents with no file changes are skipped (ErrNoChanges per-doc is not an error).
	// Returns wrapped ErrNoChanges only if no document was changed at all.
	AddMultiDocumentVersion(ctx context.Context, docIDs uu.IDSlice, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) error

	// RestoreDocument restores a document from a HashedDocument backup.
	//
	// The doc is first validated via doc.Validate(); any error is returned
	// before any state is touched.
	//
	// If recreate is true (replace): an existing document with the same ID is
	// deleted first (including its company-document marker), then recreated
	// from doc. The on-disk CompanyID after the call equals doc.CompanyID.
	//
	// Every version is written with the company of that version
	// (HashedDocument.VersionCompanyID), so a document that was moved between
	// companies is restored with its move history rather than with every
	// version filed under its current company. doc.Validate() requires the
	// latest version to name doc.CompanyID, so the restored document is owned
	// by and listed under doc.CompanyID.
	//
	// WARNING: recreate is NOT atomic with respect to the pre-existing
	// document. It is deleted before the replacement is written, so if the
	// restore fails partway the original is gone and the rollback only removes
	// what this call created — it cannot bring the original back. The document
	// is left absent until the restore is retried. This is safe for the common
	// SyncDocument flow, where the source still holds the data and the sync can
	// simply be re-run, but callers must not delete their source on a failed
	// recreate restore.
	//
	// If recreate is false (additive merge):
	//   - If the document does not exist on disk, it is created from doc —
	//     identical effect to recreate=true on a non-existing document.
	//   - If the document exists, its on-disk CompanyID must equal the company
	//     doc names for the latest version on disk (CheckRestoreCompanyID). On
	//     mismatch the call returns an error and changes nothing. Newer
	//     versions in doc that move the document to another company are
	//     restored as the move they are, and the document ends up owned by the
	//     company of its latest version.
	//   - For every version v in doc.Versions: if v is already stored with all
	//     of its files it is kept as-is (no overwrite, no error); otherwise
	//     what is missing is written.
	//   - Versions on disk that are not in doc.Versions are kept as-is.
	//
	// A version counts as already stored only if its file content is actually
	// there. An implementation split into a metadata and a file store must not
	// decide this from the metadata alone: the two can be populated
	// independently, so existing version metadata does not prove that the files
	// were ever written, and skipping on that basis reports a successful
	// restore for a document that is missing file content.
	//
	// Each version is written as a single unit (file content + per-version
	// metadata + company marker). On error mid-restore, partial state created
	// during the call is rolled back; versions successfully written before
	// the failing one stay written.
	//
	// Returns wrapped ErrNotImplemented if the implementation does not
	// support restoration.
	RestoreDocument(ctx context.Context, doc *HashedDocument, recreate bool) error
}
