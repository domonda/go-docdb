package docdb

import (
	"context"

	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
)

type DocumentStore interface {
	CreateDocument(
		ctx context.Context,
		docID uu.ID,
		files []fs.FileReader,
	) error

	// DocumentExists returns true if a document with the passed docID exists in the store
	DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error)

	// EnumDocumentIDs calls the passed callback with the ID of every document in the store
	EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error

	DocumentHashFileProvider(
		ctx context.Context,
		docID uu.ID,
		fileHashes []string,
	) (FileProvider, error)

	ReadDocumentHashFile(
		ctx context.Context,
		docID uu.ID,
		filename,
		hash string,
	) (data []byte, err error)

	DeleteDocument(ctx context.Context, docID uu.ID) error

	DeleteDocumentHashes(
		ctx context.Context,
		docID uu.ID,
		hashes []string,
	) error
}
