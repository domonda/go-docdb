package docdb

import (
	"context"

	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
)

type DocumentStore interface {
	CreateDocument(ctx context.Context, docID uu.ID, version VersionTime, files []fs.FileReader) error

	// DocumentExists returns true if a document with the passed docID exists in the store
	DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error)

	// EnumDocumentIDs calls the passed callback with the ID of every document in the store
	EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error

	// DocumentVersionFileProvider returns a FileProvider for the files of a document version
	DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version VersionTime) (FileProvider, error)

	// ReadDocumentVersionFile returns the contents of a file of a document version.
	// Wrapped ErrDocumentNotFound, ErrDocumentVersionNotFound, ErrDocumentFileNotFound
	// will be returned in case of such error conditions.
	ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version VersionTime, filename string) (data []byte, err error)

	DeleteDocument(ctx context.Context, docID uu.ID) error

	DeleteDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) error
}
