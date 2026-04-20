package docdb

import (
	"context"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

// DocumentStore is the interface for storing and retrieving document file content
// by content hash. It is used together with MetadataStore by the split-store
// Conn implementation returned by NewConn.
//
// Implementations must return the typed errors from this package when the
// documented not-found conditions occur, so callers can match them with
// errors.Is: ErrDocumentNotFound, ErrDocumentFileNotFound.
type DocumentStore interface {
	// CreateDocument stores the provided files for a document version.
	// Files are keyed by their content hash, so identical content is
	// deduplicated. Uniqueness of the document ID is enforced by the
	// MetadataStore, not by this method.
	CreateDocument(ctx context.Context, docID uu.ID, version VersionTime, files []fs.FileReader) error

	// DocumentExists returns true if a document with the passed docID exists in the store.
	DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error)

	// EnumDocumentIDs calls the passed callback with the ID of every document in the store.
	// If the callback returns an error, enumeration stops and the error is returned.
	EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error

	// DocumentHashFileProvider returns a FileProvider that can read files
	// identified by the given content hashes for a document.
	// The returned FileProvider returns ErrDocumentFileNotFound from ReadFile
	// for filenames that are not part of the provided hashes.
	DocumentHashFileProvider(ctx context.Context, docID uu.ID, fileHashes []string) (FileProvider, error)

	// ReadDocumentHashFile reads a single file identified by its content hash.
	// Returns ErrDocumentFileNotFound if no file with the given filename
	// and hash exists for the document.
	ReadDocumentHashFile(ctx context.Context, docID uu.ID, filename, hash string) (data []byte, err error)

	// DeleteDocument deletes all stored files for a document.
	// Returns ErrDocumentNotFound if the document does not exist.
	DeleteDocument(ctx context.Context, docID uu.ID) error

	// DeleteDocumentHashes deletes specific content hashes for a document.
	// Returns ErrDocumentNotFound if the document does not exist.
	// Hashes that do not match any stored file are silently ignored.
	DeleteDocumentHashes(ctx context.Context, docID uu.ID, hashes []string) error
}
