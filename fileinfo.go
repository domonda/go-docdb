package docdb

import (
	"bytes"
	"context"

	"github.com/domonda/go-errs"
	"github.com/ungerik/go-fs"
	"github.com/ungerik/go-fs/fsimpl"
)

type FileInfo struct {
	Name string
	Size int64
	Hash string
}

// ContentHash returns a Dropbox compatible 64 hex character content hash
// by reading from an io.Reader until io.EOF.
// See https://www.dropbox.com/developers/reference/content-hash
func ContentHash(data []byte) string {
	hash, err := fsimpl.DropboxContentHash(context.Background(), bytes.NewReader(data))
	if err != nil {
		panic(errs.Errorf("should never happen: %w", err))
	}
	return hash
}

// ReadFileInfo reads the file content from file and returns a FileInfo with the file name, size and hash.
func ReadFileInfo(ctx context.Context, file fs.FileReader) (info FileInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, file)

	data, err := file.ReadAllContext(ctx)
	if err != nil {
		return FileInfo{}, err
	}
	info.Name = file.Name()
	info.Size = int64(len(data))
	info.Hash, err = fsimpl.DropboxContentHash(ctx, bytes.NewReader(data))
	if err != nil {
		return FileInfo{}, err
	}
	return info, nil
}
