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
// single file "a.txt" with the given content. It reuses the package's fakes
// from fakes_test.go. The version invariant checks run before any store write,
// so neither fake store needs to be functional beyond the latest-version
// lookup and the previous-file provider.
func singleFileBackend(content []byte) (*fakeMetadataStore, docdb.Conn, uu.ID) {
	docID := uu.IDv4()
	companyID := uu.IDv4()
	meta := newFakeMetadataStore(&docdb.VersionInfo{
		DocID:     docID,
		CompanyID: companyID,
		Version:   docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000"),
		Files: map[string]docdb.FileInfo{
			"a.txt": {Name: "a.txt", Size: int64(len(content)), Hash: docdb.ContentHash(content)},
		},
	})
	docs := newFakeDocumentStore()
	docs.prevFiles = []fs.FileReader{fs.NewMemFile("a.txt", content)}
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
	require.Empty(t, meta.deletedVersions, "must be rejected before any metadata commit/rollback")
}

// TestConn_AddDocumentVersion_NoChanges verifies that a version which changes
// neither the files nor the company is refused as docdb.ErrNoChanges, the
// answer docdb.Conn documents for every implementation and localfsdb has always
// given. A change-less version is also one that HashedDocument.Validate
// rejects, so committing it would produce a document that can no longer be
// backed up, synced or restored.
func TestConn_AddDocumentVersion_NoChanges(t *testing.T) {
	content := []byte("a content")
	meta, conn, docID := singleFileBackend(content)

	// Rewriting the only file with byte-identical content changes nothing.
	err := conn.AddDocumentVersion(context.Background(), docID, uu.IDv4(), "rewrite identical content",
		docdb.CreateVersionWriteFiles(fs.NewMemFile("a.txt", content)),
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)
	require.ErrorIs(t, err, docdb.ErrNoChanges)
	require.Empty(t, meta.insertedVersions, "no version may be committed for a change-less version")
}

// TestConn_AddDocumentVersion_CompanyChangeIsAChange verifies that moving a
// document to another company is committed as a version even though it changes
// no file: that version is what records the move in the document's history, and
// what makes the document belong to and be listed under the new company.
func TestConn_AddDocumentVersion_CompanyChangeIsAChange(t *testing.T) {
	content := []byte("a content")
	meta, conn, docID := singleFileBackend(content)
	newCompanyID := uu.IDv4()
	newVersion := docdb.MustVersionTimeFromString("2024-01-02_00-00-00.000")

	var committed *docdb.VersionInfo
	err := conn.AddDocumentVersion(context.Background(), docID, uu.IDv4(), "USER_DOCUMENT_MOVE",
		func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
			return &docdb.CreateVersionResult{Version: newVersion, NewCompanyID: newCompanyID.Nullable()}, nil
		},
		func(_ context.Context, versionInfo *docdb.VersionInfo) error {
			committed = versionInfo
			return nil
		},
	)
	require.NoError(t, err)
	require.Equal(t, []docdb.VersionTime{newVersion}, meta.insertedVersions)
	require.NotNil(t, committed)
	require.Equal(t, newCompanyID, committed.CompanyID)
}
