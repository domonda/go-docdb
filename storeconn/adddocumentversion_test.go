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
func singleFileBackend(content []byte) (*fakeMetadataStore, *fakeDocumentStore, docdb.Conn, uu.ID) {
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
	return meta, docs, storeconn.New(docs, meta), docID
}

// TestConn_AddDocumentVersion_RemoveAllFilesRejected verifies that storeconn
// rejects a new version that would remove every file, before committing any
// metadata.
func TestConn_AddDocumentVersion_RemoveAllFilesRejected(t *testing.T) {
	content := []byte("a content")
	meta, _, conn, docID := singleFileBackend(content)

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
	meta, _, conn, docID := singleFileBackend(content)

	// Rewriting the only file with byte-identical content changes nothing.
	err := conn.AddDocumentVersion(context.Background(), docID, uu.IDv4(), "rewrite identical content",
		docdb.CreateVersionWriteFiles(fs.NewMemFile("a.txt", content)),
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)
	require.ErrorIs(t, err, docdb.ErrNoChanges)
	require.Empty(t, meta.insertedVersions, "no version may be committed for a change-less version")
}

// staleSizeFile is an fs.FileReader whose Size() disagrees with the bytes
// ReadAll returns, which is what a file rewritten between the stat and the read
// looks like — and what a FileReader implementation that simply computes Size()
// from something other than its content looks like at any time.
type staleSizeFile struct {
	fs.MemFile
}

func (staleSizeFile) Size() int64 { return 999999 }

// TestConn_AddDocumentVersion_RecordsTheSizeOfTheHashedBytes verifies that a
// version records the size of the bytes it hashed, not whatever the
// FileReader's Size() reports.
//
// Size and Hash of a stored file have to describe the same content: a version
// whose Size contradicts its Hash fails every later read of it through
// ReadHashedDocument, so the document can no longer be backed up, synced or
// restored — silent, and only discovered at the next migration.
func TestConn_AddDocumentVersion_RecordsTheSizeOfTheHashedBytes(t *testing.T) {
	content := []byte("a content")
	meta, _, conn, docID := singleFileBackend(content)

	newContent := []byte("new content of b")
	var committed *docdb.VersionInfo
	err := conn.AddDocumentVersion(context.Background(), docID, uu.IDv4(), "add b",
		docdb.CreateVersionWriteFiles(staleSizeFile{fs.MemFile{FileName: "b.txt", FileData: newContent}}),
		docdb.CaptureNewVersionInfo(&committed),
	)
	require.NoError(t, err)
	require.NotEmpty(t, meta.insertedVersions)

	file := committed.Files["b.txt"]
	require.Equal(t, int64(len(newContent)), file.Size,
		"the recorded size must describe the bytes that were hashed, not the FileReader's Size()")
	require.Equal(t, docdb.ContentHash(newContent), file.Hash)
}

// TestConn_AddDocumentVersion_CompanyChangeIsAChange verifies that moving a
// document to another company is committed as a version even though it changes
// no file: that version is what records the move in the document's history, and
// what makes the document belong to and be listed under the new company.
func TestConn_AddDocumentVersion_CompanyChangeIsAChange(t *testing.T) {
	content := []byte("a content")
	meta, _, conn, docID := singleFileBackend(content)
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

// twoFacedFile returns different content on its second read, which is what a
// file rewritten between two reads looks like — and what any FileReader that
// does not guarantee a stable read looks like at any time.
type twoFacedFile struct {
	fs.MemFile
	secondRead []byte
	reads      *int
}

func (f twoFacedFile) ReadAll() ([]byte, error) {
	*f.reads++
	if *f.reads > 1 {
		return f.secondRead, nil
	}
	return f.FileData, nil
}

// TestConn_AddDocumentVersion_UploadsTheBytesItHashed verifies that the content
// handed to the DocumentStore is the content the version's hash was computed
// from.
//
// AddDocumentVersion reads each written file to derive its size and hash, and
// used to hand the same readers on to the DocumentStore, which read them a
// second time to upload. A FileReader is not required to return the same bytes
// twice, and when it does not, the version records the hash of one read while
// the store holds the other. Files are addressed by content hash, so that
// object can never be found again under the recorded hash: every later read of
// the document through ReadHashedDocument fails, silently, until a backup or
// migration trips over it.
func TestConn_AddDocumentVersion_UploadsTheBytesItHashed(t *testing.T) {
	_, docs, conn, docID := singleFileBackend([]byte("a content"))

	var (
		hashed  = []byte("the bytes the metadata describes")
		rewrite = []byte("what a second read would have returned")
		reads   int
	)

	var committed *docdb.VersionInfo
	err := conn.AddDocumentVersion(context.Background(), docID, uu.IDv4(), "add b",
		docdb.CreateVersionWriteFiles(twoFacedFile{
			MemFile:    fs.MemFile{FileName: "b.txt", FileData: hashed},
			secondRead: rewrite,
			reads:      &reads,
		}),
		docdb.CaptureNewVersionInfo(&committed),
	)
	require.NoError(t, err)

	recorded := committed.Files["b.txt"]
	require.Equal(t, docdb.ContentHash(hashed), recorded.Hash)
	require.Contains(t, docs.stored, docdb.FileInfo{Name: "b.txt", Hash: recorded.Hash},
		"the stored object must be the content the recorded hash names")
	require.NotContains(t, docs.stored, docdb.FileInfo{Name: "b.txt", Hash: docdb.ContentHash(rewrite)},
		"a second read of the file must not reach the store")
}
