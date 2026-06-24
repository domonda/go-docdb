package storeconn_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/storeconn"
)

// singleFileBackend builds a storeconn.Conn whose latest version contains a
// single file "a.txt" with the given content. It reuses the fakes from
// rollback_test.go. The version invariant checks run before any store write,
// so neither fake store needs to be functional beyond the latest-version
// lookup and the previous-file provider.
func singleFileBackend(content []byte) (*fakeMetadataStore, docdb.Conn, uu.ID) {
	docID := uu.IDv4()
	companyID := uu.IDv4()
	meta := &fakeMetadataStore{
		latest: &docdb.VersionInfo{
			DocID:     docID,
			CompanyID: companyID,
			Version:   docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000"),
			Files: map[string]docdb.FileInfo{
				"a.txt": {Name: "a.txt", Size: int64(len(content)), Hash: docdb.ContentHash(content)},
			},
		},
	}
	docs := &fakeDocumentStore{prevFiles: []fs.FileReader{fs.NewMemFile("a.txt", content)}}
	return meta, storeconn.New(docs, meta), docID
}

// TestConn_AddDocumentVersion_RemoveAllFilesRejected verifies that storeconn
// rejects a new version that would remove every file, before committing any
// metadata.
func TestConn_AddDocumentVersion_RemoveAllFilesRejected(t *testing.T) {
	content := []byte("a content")
	meta, conn, docID := singleFileBackend(content)

	err := conn.AddDocumentVersion(context.Background(), docID, uu.IDv4(), "remove all",
		docdb.CreateVersionRemoveFiles("a.txt"),
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)
	require.Error(t, err)
	require.NotErrorIs(t, err, docdb.ErrNoChanges)
	require.ErrorContains(t, err, "at least one file")
	require.False(t, meta.deleteVersionCalled, "must be rejected before any metadata commit/rollback")
}

// TestConn_AddDocumentVersion_NoChangeRejected verifies that storeconn returns
// ErrNoChanges when the new version's files are identical to the previous one,
// matching the documented contract and localfsdb's behavior.
func TestConn_AddDocumentVersion_NoChangeRejected(t *testing.T) {
	content := []byte("a content")
	meta, conn, docID := singleFileBackend(content)

	// Writing a.txt with identical content yields no change.
	err := conn.AddDocumentVersion(context.Background(), docID, uu.IDv4(), "no change",
		docdb.CreateVersionWriteFiles(fs.NewMemFile("a.txt", content)),
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)
	require.ErrorIs(t, err, docdb.ErrNoChanges)
	require.False(t, meta.deleteVersionCalled, "must be rejected before any metadata commit/rollback")
}
