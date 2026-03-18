package docdb

import (
	"context"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

// MetadataStore is the interface for storing and querying document version metadata.
// It is used together with DocumentStore by the split-store
// Conn implementation returned by NewConn.
type MetadataStore interface {
	// CreateDocument creates metadata for a new document with its initial version.
	CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, version VersionTime, files []fs.FileReader) (*VersionInfo, error)

	// AddDocumentVersion adds metadata for a new version of an existing document.
	AddDocumentVersion(
		ctx context.Context,
		newVersion VersionTime,
		previousVersion VersionTime,
		docID uu.ID,
		companyID uu.ID,
		userID uu.ID,
		reason string,
		addedFiles []*FileInfo,
		modifiedFiles []*FileInfo,
		removedFiles []string,
	) (*VersionInfo, error)

	// DocumentCompanyID returns the companyID for a docID.
	DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error)

	// SetDocumentCompanyID changes the companyID for a document.
	SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error

	// DocumentVersions returns all version timestamps of a document in ascending order.
	// Returns ErrDocumentNotFound if the document does not exist.
	DocumentVersions(ctx context.Context, docID uu.ID) ([]VersionTime, error)

	// LatestDocumentVersion returns the latest VersionTime of a document.
	LatestDocumentVersion(ctx context.Context, docID uu.ID) (VersionTime, error)

	// EnumCompanyDocumentIDs calls the passed callback with the ID of every document of a company in the database.
	EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error

	// DocumentVersionInfo returns the VersionInfo for a specific version of a document.
	DocumentVersionInfo(ctx context.Context, docID uu.ID, version VersionTime) (*VersionInfo, error)

	// LatestDocumentVersionInfo returns the VersionInfo for the latest version of a document.
	LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*VersionInfo, error)

	// DeleteDocument deletes all version metadata for a document.
	DeleteDocument(ctx context.Context, docID uu.ID) error

	// DeleteDocumentVersion deletes metadata for a specific version of a document
	// and returns the remaining versions and content hashes that should be deleted.
	DeleteDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) (leftVersions []VersionTime, hashesToDelete []string, err error)
}
