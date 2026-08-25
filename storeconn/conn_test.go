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

// TestConn_RestoreDocument_InvalidDocument verifies that RestoreDocument
// rejects a structurally invalid HashedDocument before touching either store,
// so the nil stores below are never dereferenced.
func TestConn_RestoreDocument_InvalidDocument(t *testing.T) {
	conn := storeconn.New(nil, nil)
	err := conn.RestoreDocument(context.Background(), &docdb.HashedDocument{}, false)
	require.Error(t, err)
}

// TestConn_CreateDocument_RejectsEmptyFiles verifies that a document cannot be
// created without files: its first version must contain at least one file. The
// check runs before either store is accessed, so the nil stores are never
// dereferenced.
func TestConn_CreateDocument_RejectsEmptyFiles(t *testing.T) {
	conn := storeconn.New(nil, nil)
	err := conn.CreateDocument(
		context.Background(),
		uu.IDv4(), uu.IDv4(), uu.IDv4(),
		"reason",
		docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000"),
		nil, // no files
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)
	require.Error(t, err)
}

// TestConn_CreateDocument_RecordsTheSizeOfTheHashedBytes verifies that the
// genesis version records the size of the bytes it hashed, not whatever the
// FileReader's Size() reports — the same guarantee
// TestConn_AddDocumentVersion_RecordsTheSizeOfTheHashedBytes makes for every
// later version.
//
// Size and Hash of a stored file have to describe the same content: a version
// whose Size contradicts its Hash fails every later read of it through
// ReadHashedDocument, so the document can no longer be backed up, synced or
// migrated. On the genesis path that condemns the document from its very first
// version, which is why the guarantee cannot hold for AddDocumentVersion alone.
func TestConn_CreateDocument_RecordsTheSizeOfTheHashedBytes(t *testing.T) {
	content := []byte("genesis content")
	meta := newFakeMetadataStore()
	conn := storeconn.New(newFakeDocumentStore(), meta)

	err := conn.CreateDocument(
		context.Background(),
		uu.IDv4(), uu.IDv4(), uu.IDv4(),
		"genesis",
		docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000"),
		[]fs.FileReader{staleSizeFile{fs.MemFile{FileName: "a.txt", FileData: content}}},
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)
	require.NoError(t, err)
	require.Len(t, meta.createInputs, 1)

	addedFiles := meta.createInputs[0].AddedFiles
	require.Len(t, addedFiles, 1)
	require.Equal(t, int64(len(content)), addedFiles[0].Size,
		"the recorded size must describe the bytes that were hashed, not the FileReader's Size()")
	require.Equal(t, docdb.ContentHash(content), addedFiles[0].Hash)
}

// TestConn_CreateDocument_PersistsAddedFilesSorted verifies that a document
// created directly — not through a restore — records its first version's added
// files sorted by filename rather than in the order the caller passed them.
//
// docdb.VersionInfo.SetFileDeltas sorts every change list it derives and
// documents why: the lists are compared across implementations, and localfsdb
// derives its own through SetFileDeltas. CreateDocument records every file as
// added without going through it, so the same document created from the same
// files persisted a different order in the two stores. VersionInfo compares
// the lists order-insensitively, so nothing fails — the divergence only shows
// up in the stored data.
func TestConn_CreateDocument_PersistsAddedFilesSorted(t *testing.T) {
	meta := newFakeMetadataStore()
	conn := storeconn.New(newFakeDocumentStore(), meta)

	// Passed in an order that is neither sorted nor reverse-sorted, so a
	// implementation that simply reversed would not pass either.
	names := []string{"d.txt", "a.txt", "c.txt", "b.txt"}
	files := make([]fs.FileReader, len(names))
	for i, name := range names {
		files[i] = fs.NewMemFile(name, []byte("content of "+name))
	}

	err := conn.CreateDocument(
		context.Background(),
		uu.IDv4(), uu.IDv4(), uu.IDv4(),
		"genesis",
		docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000"),
		files,
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)
	require.NoError(t, err)
	require.Len(t, meta.createInputs, 1)

	addedNames := make([]string, 0, len(meta.createInputs[0].AddedFiles))
	for _, file := range meta.createInputs[0].AddedFiles {
		addedNames = append(addedNames, file.Name)
	}
	require.Equal(t, []string{"a.txt", "b.txt", "c.txt", "d.txt"}, addedNames,
		"added files must be persisted sorted by filename, not in the caller's argument order")
}
