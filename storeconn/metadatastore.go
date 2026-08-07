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
	// RelinkSuccessor, when non-nil, names the one version that must be
	// relinked to chain off NewVersion instead of PreviousVersion, because this
	// version is being filled back into an existing chain rather than appended
	// to its end. DeleteDocumentVersion relinks a deleted version's successor
	// to the deleted version's own predecessor, so restoring the removed
	// version has to undo exactly that. Only RestoreDocument sets it, to the
	// backup's own next version after NewVersion.
	//
	// The successor is named rather than found, because no property of the
	// stored rows identifies it. Relinking whichever version happens to chain
	// off PreviousVersion and sort after NewVersion captures two rows that are
	// not this version's successor:
	//
	//   - A concurrent append. Both appends chain off the version they read as
	//     the latest, and the second to insert must be refused (see
	//     MetadataStore.CreateDocumentVersion), not adopted: its file set was
	//     carried forward from before the other's change, so taking it over
	//     drops that change from every version after it. The version
	//     timestamps do not order the inserts either — a CreateVersionFunc
	//     stamps its version when it starts, so a slower writer can hold the
	//     earlier timestamp.
	//   - A version that exists only on the destination of a merge-restore and
	//     is absent from the backup. Conn.RestoreDocument keeps such versions
	//     as-is; relinking one onto a restored version would leave it naming a
	//     predecessor whose file set it never derived from.
	//
	// A named successor that is not stored, or is stored but does not chain off
	// PreviousVersion, relinks nothing and is not an error: the backup's next
	// version may simply not be on the destination yet.
	RelinkSuccessor *docdb.VersionTime
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
	// A version that is already stored must be reported as
	// docdb.ErrVersionAlreadyExists, a duplicate genesis version as
	// docdb.ErrDocumentAlreadyExists. RestoreDocument relies on that to resume a
	// copy whose metadata was written but whose file content was not: it calls
	// this for such a version and treats the rejection as the expected answer.
	// An implementation may instead verify the passed input against the stored
	// version and return that version without inserting.
	//
	// A document's versions form a chain, so a version has at most one
	// successor: a second version naming an already-used in.PreviousVersion
	// must be refused as docdb.ErrDocumentChanged rather than stored. That is
	// the optimistic concurrency conflict between two AddDocumentVersion calls
	// that read the same latest version, and the loser has to redo its work
	// from the new latest version instead of writing a file set that never saw
	// the winner's change. An implementation must not tell the two apart by
	// their version timestamps: a CreateVersionFunc stamps its version when it
	// starts, so the writer that inserts second may hold either one. An
	// existing version becomes this one's successor only when in.RelinkSuccessor
	// names it, and only RestoreDocument names one.
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
