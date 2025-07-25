package docdb

import (
	"context"

	"github.com/domonda/go-types/uu"
)

type MetadataStore interface {
	// DocumentCompanyID returns the companyID for a docID
	DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error)

	// SetDocumentCompanyID changes the companyID for a document
	SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error

	// DocumentVersions returns all version timestamps of a document in ascending order.
	// Returns nil and no error if the document does not exist or has no versions.
	DocumentVersions(ctx context.Context, docID uu.ID) ([]VersionTime, error)

	// LatestDocumentVersion returns the lates VersionTime of a document
	LatestDocumentVersion(ctx context.Context, docID uu.ID) (VersionTime, error)
}
