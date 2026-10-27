package docdb_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/localfsdb"
	"github.com/domonda/go-types/uu"
)

// TestCopyDocumentFiles checks that a backup made by CopyDocumentFiles reads
// back as the same document. The backup has the layout of a localfsdb
// documents directory, so it is read back by opening a localfsdb.Conn on it.
func TestCopyDocumentFiles(t *testing.T) {
	var (
		ctx       = t.Context()
		companyID = uu.IDFrom("6f296458-24cd-4146-ac3a-33ca885a993e")
		docID     = uu.IDFrom("c538ac93-2cf0-49a9-8378-22cd48b5ab84")
		userID    = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		v0        = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")
		v1        = docdb.MustVersionTimeFromString("2023-01-02_00-00-00.000")
		v2        = docdb.MustVersionTimeFromString("2023-01-03_00-00-00.000")
		noopOnNew = func(context.Context, *docdb.VersionInfo) error { return nil }
	)

	source := localfsdb.NewTestConn(t)
	addVersion := func(version docdb.VersionTime, file fs.MemFile) {
		t.Helper()
		require.NoError(t, source.AddDocumentVersion(
			ctx, docID, userID, version.String(),
			func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
				return &docdb.CreateVersionResult{Version: version, WriteFiles: []fs.FileReader{file}}, nil
			},
			noopOnNew,
		))
	}
	requireBackupEqualsSource := func(backup docdb.Conn) {
		t.Helper()
		want, err := docdb.ReadHashedDocument(ctx, source, docID)
		require.NoError(t, err)
		got, err := docdb.ReadHashedDocument(ctx, backup, docID)
		require.NoError(t, err)
		require.Equal(t, want, got)
	}

	// given a document with two versions
	require.NoError(t, source.CreateDocument(
		ctx, companyID, docID, userID, "v0", v0,
		[]fs.FileReader{fs.NewMemFile("a.txt", []byte("A"))},
		noopOnNew,
	))
	addVersion(v1, fs.NewMemFile("b.txt", []byte("B")))

	// when it is copied to a backup directory
	backupDir := fs.File(t.TempDir())
	_, err := docdb.CopyDocumentFiles(ctx, source, docID, backupDir, false)
	require.NoError(t, err)

	// then the backup reads back as the same document
	backup := localfsdb.NewConn(backupDir, fs.File(t.TempDir()))
	requireBackupEqualsSource(backup)

	// and a second copy without overwrite refuses the existing backup
	_, err = docdb.CopyDocumentFiles(ctx, source, docID, backupDir, false)
	require.ErrorContains(t, err, "already exists")

	// and a copy with overwrite writes over the existing version directories
	// and takes in a version added since
	addVersion(v2, fs.NewMemFile("c.txt", []byte("C")))
	_, err = docdb.CopyDocumentFiles(ctx, source, docID, backupDir, true)
	require.NoError(t, err)
	requireBackupEqualsSource(backup)
}
