package storeconn

import (
	"context"

	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
)

// DocumentStore is the interface for storing and retrieving document file content
// by content hash. It is used together with MetadataStore by the split-store
// docdb.Conn implementation returned by New.
//
// Implementations must return the typed errors from the docdb package when the
// documented not-found conditions occur, so callers can match them with
// errors.Is: docdb.ErrDocumentNotFound, docdb.ErrDocumentFileNotFound.
type DocumentStore interface {
	// CreateDocumentVersion stores the provided files for a document version
	// and returns a FileInfo (name, size, content hash) for each stored file in
	// the same order as files. Returning the hashes the store computed while
	// writing lets the caller avoid re-reading and re-hashing the files. Files
	// are keyed by their content hash, so identical content is deduplicated.
	// Uniqueness of the document ID is enforced by the MetadataStore, not by
	// this method.
	CreateDocumentVersion(ctx context.Context, docID uu.ID, version docdb.VersionTime, files []fs.FileReader) ([]*docdb.FileInfo, error)

	// DocumentExists returns true if a document with the passed docID exists in the store.
	DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error)

	// DocumentHashFilesExist reports for every passed file whether the store
	// holds a file with that name and content hash for the document. The result
	// has one element per passed file in the same order, and is empty for no
	// passed files. Only the Name and Hash of a FileInfo are used, never Size.
	//
	// A store does not track versions — files are addressed by name and content
	// hash — so this is how a caller determines whether a complete version is
	// present: a version is stored if and only if all of its files are. The
	// batch shape exists so that check costs one round trip for a whole
	// document instead of one per file.
	DocumentHashFilesExist(ctx context.Context, docID uu.ID, files []docdb.FileInfo) (exist []bool, err error)

	// DocumentHashFileProvider returns a FileProvider that can read files
	// identified by the given content hashes for a document.
	// The returned FileProvider returns ErrDocumentFileNotFound from ReadFile
	// for filenames that are not part of the provided hashes.
	DocumentHashFileProvider(ctx context.Context, docID uu.ID, fileHashes []string) (docdb.FileProvider, error)

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
