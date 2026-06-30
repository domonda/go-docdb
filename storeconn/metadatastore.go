package storeconn

import (
	"context"

	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb"
)

// CreateDocumentVersionInput holds the arguments for
// MetadataStore.CreateDocumentVersion.
type CreateDocumentVersionInput struct {
	DocID     uu.ID
	CompanyID uu.ID
	UserID    uu.ID
	Reason    string
	// NewVersion is the version timestamp to write.
	NewVersion docdb.VersionTime
	// PreviousVersion is nil for the first (genesis) version, or the version
	// whose files are carried forward when appending to an existing document.
	PreviousVersion *docdb.VersionTime
	// AddedFiles and ModifiedFiles carry the already-computed FileInfo (name,
	// size, content hash); CreateDocumentVersion does not read file content.
	AddedFiles    []*docdb.FileInfo
	ModifiedFiles []*docdb.FileInfo
	RemovedFiles  []string
	// Files, when non-nil, is the complete resolved file set of the new version
	// (filename → FileInfo). A caller that has already computed it — for example
	// AddDocumentVersion, which derives it to enforce that a version keeps at
	// least one file — can pass it so the store skips looking PreviousVersion up
	// and re-deriving the carry-forward + delta set. When nil, the store builds
	// the set from PreviousVersion's files plus AddedFiles/ModifiedFiles/
	// RemovedFiles. The store uses the map directly without copying it, so the
	// caller must not mutate it after the call. AddedFiles/ModifiedFiles/
	// RemovedFiles are still recorded as the version's change lists either way.
	Files map[string]docdb.FileInfo
}

// MetadataStore is the interface for storing and querying document version metadata.
// It is used together with DocumentStore by the split-store
// docdb.Conn implementation returned by New.
type MetadataStore interface {
	// CreateDocumentVersion writes metadata for a new document version.
	//
	// A nil in.PreviousVersion creates the first (genesis) version of a new
	// document: prev_version is stored as NULL and every passed file is
	// recorded as an added file. A non-nil in.PreviousVersion appends a version
	// to an existing document, carrying that version's files forward before
	// applying the added/modified/removed deltas.
	//
	// Returns the resulting full VersionInfo.
	CreateDocumentVersion(ctx context.Context, in CreateDocumentVersionInput) (*docdb.VersionInfo, error)

	// DocumentCompanyID returns the companyID for a docID.
	DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error)

	// SetDocumentCompanyID changes the companyID for a document.
	SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error

	// DocumentVersions returns all version timestamps of a document in ascending order.
	// Returns ErrDocumentNotFound if the document does not exist.
	DocumentVersions(ctx context.Context, docID uu.ID) ([]docdb.VersionTime, error)

	// LatestDocumentVersion returns the latest VersionTime of a document.
	LatestDocumentVersion(ctx context.Context, docID uu.ID) (docdb.VersionTime, error)

	// CompanyIDs returns the IDs of all companies that have documents in the
	// database, sorted by ID for a consistent order.
	// Returns nil if there are no companies.
	CompanyIDs(ctx context.Context) (uu.IDSlice, error)

	// CompanyDocumentIDs returns the IDs of all documents of a company in the
	// database, sorted by ID for a consistent order.
	// Returns nil if the company has no documents.
	CompanyDocumentIDs(ctx context.Context, companyID uu.ID) (uu.IDSlice, error)

	// DocumentVersionInfo returns the VersionInfo for a specific version of a document.
	DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error)

	// LatestDocumentVersionInfo returns the VersionInfo for the latest version of a document.
	LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*docdb.VersionInfo, error)

	// DeleteDocument deletes all version metadata for a document.
	DeleteDocument(ctx context.Context, docID uu.ID) error

	// DeleteDocumentVersion deletes metadata for a specific version of a document
	// and returns the remaining versions and content hashes that should be deleted.
	DeleteDocumentVersion(ctx context.Context, docID uu.ID, version docdb.VersionTime) (leftVersions []docdb.VersionTime, hashesToDelete []string, err error)
}
