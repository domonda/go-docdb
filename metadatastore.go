package docdb

import (
	"context"

	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
)

type MetadataStore interface {
	CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, files []fs.FileReader) (*VersionInfo, error)

	// DocumentCompanyID returns the companyID for a docID
	DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error)

	// SetDocumentCompanyID changes the companyID for a document
	SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error

	// DocumentVersions returns all version timestamps of a document in ascending order.
	// Returns nil and no error if the document does not exist or has no versions.
	DocumentVersions(ctx context.Context, docID uu.ID) ([]VersionTime, error)

	LatestDocumentVersion(ctx context.Context, docID uu.ID) (VersionTime, error)

	// EnumCompanyDocumentIDs calls the passed callback with the ID of every document of a company in the database
	EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error

	DocumentVersionInfo(ctx context.Context, docID uu.ID, version VersionTime) (*VersionInfo, error)

	LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*VersionInfo, error)

	DeleteDocument(ctx context.Context, docID uu.ID) error

	DeleteDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) (leftVersions []VersionTime, hashesToDelete []string, err error)
}
