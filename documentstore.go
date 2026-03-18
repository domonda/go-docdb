package docdb

import (
	"context"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

// DocumentStore is the interface for storing and retrieving document file content
// by content hash. It is used together with MetadataStore by the split-store
// Conn implementation returned by NewConn.
type DocumentStore interface {
	// CreateDocument stores the provided files for a document version.
	CreateDocument(
		ctx context.Context,
		docID uu.ID,
		version VersionTime,
		files []fs.FileReader,
	) error

	// DocumentExists returns true if a document with the passed docID exists in the store.
	DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error)

	// EnumDocumentIDs calls the passed callback with the ID of every document in the store.
	EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error

	// DocumentHashFileProvider returns a FileProvider that can read files
	// identified by the given content hashes for a document.
	DocumentHashFileProvider(
		ctx context.Context,
		docID uu.ID,
		fileHashes []string,
	) (FileProvider, error)

	// ReadDocumentHashFile reads a single file identified by its content hash.
	ReadDocumentHashFile(
		ctx context.Context,
		docID uu.ID,
		filename,
		hash string,
	) (data []byte, err error)

	// DeleteDocument deletes all stored files for a document.
	DeleteDocument(ctx context.Context, docID uu.ID) error

	// DeleteDocumentHashes deletes specific content hashes for a document.
	DeleteDocumentHashes(
		ctx context.Context,
		docID uu.ID,
		hashes []string,
	) error
}
