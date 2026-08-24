package storeconn_test

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/storeconn"
)

// TestConn_AddDocumentVersion_RollbackKeepsSharedBlob verifies that when adding
// a new version fails after its metadata is committed, the rollback deletes only
// the blobs the metadata store reports as referenced solely by the rolled-back
// version — never a blob whose content hash is still shared with a sibling
// version. Deleting by the new version's added/modified hashes directly (as the
// previous implementation did) would wipe the sibling's blob, since blob content
// is deduplicated by hash across the whole document.
func TestConn_AddDocumentVersion_RollbackKeepsSharedBlob(t *testing.T) {
	content := []byte("shared content")
	sharedHash := docdb.ContentHash(content)
	v1 := docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")

	cases := []struct {
		name         string
		createErr    error
		onNewVersion docdb.OnNewVersionFunc
	}{
		{
			name:         "blob write fails",
			createErr:    errors.New("blob write failed"),
			onNewVersion: func(context.Context, *docdb.VersionInfo) error { return nil },
		},
		{
			name:         "onNewVersion fails",
			createErr:    nil,
			onNewVersion: func(context.Context, *docdb.VersionInfo) error { return errors.New("validation gate rejected") },
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ctx := context.Background()
			docID := uu.IDv4()
			companyID := uu.IDv4()
			userID := uu.IDv4()

			meta := newFakeMetadataStore(&docdb.VersionInfo{
				DocID:     docID,
				CompanyID: companyID,
				Version:   v1,
				Files: map[string]docdb.FileInfo{
					"logo.png": {Name: "logo.png", Size: int64(len(content)), Hash: sharedHash},
				},
			})
			// logo.png in v1 still references sharedHash, so deleting the new
			// version reports nothing safe to delete.
			meta.safeHashesToDelete = nil

			docs := newFakeDocumentStore()
			docs.prevFiles = []fs.FileReader{fs.NewMemFile("logo.png", content)}
			docs.createErr = tc.createErr
			conn := storeconn.New(docs, meta)

			// The new version adds icon.png with the same content as v1's
			// logo.png, so its added-file hash collides with a blob the sibling
			// version still uses.
			err := conn.AddDocumentVersion(ctx, docID, userID, "add icon",
				docdb.CreateVersionWriteFiles(fs.NewMemFile("icon.png", content)),
				tc.onNewVersion,
			)

			require.Error(t, err)                     // the failure surfaces to the caller
			require.NotEmpty(t, meta.deletedVersions) // the metadata version was rolled back
			require.NotContains(t, docs.deletedHashes, sharedHash,
				"rollback must not delete a blob whose hash is shared with a sibling version")
		})
	}
}

// TestConn_AddDocumentVersion_RollsBackOnPanic verifies that a panic from a
// store after the metadata version is committed is rolled back like an error.
//
// The rollback runs from a deferred closure keyed on the returned error, and a
// panic is not one, so it would travel past the rollback and leave exactly the
// committed-metadata-without-file-content state RestoreDocument has to detect
// and repair — while the caller sees a panic instead of an error.
func TestConn_AddDocumentVersion_RollsBackOnPanic(t *testing.T) {
	ctx := context.Background()
	docID := uu.IDv4()
	companyID := uu.IDv4()
	userID := uu.IDv4()
	content := []byte("a content")
	v1 := docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
	newVersion := docdb.MustVersionTimeFromString("2024-01-02_00-00-00.000")

	meta := newFakeMetadataStore(&docdb.VersionInfo{
		DocID:     docID,
		CompanyID: companyID,
		Version:   v1,
		Files: map[string]docdb.FileInfo{
			"a.txt": {Name: "a.txt", Size: int64(len(content)), Hash: docdb.ContentHash(content)},
		},
	})
	docs := newFakeDocumentStore()
	docs.prevFiles = []fs.FileReader{fs.NewMemFile("a.txt", content)}
	docs.panicOn = &newVersion // the blob write panics after the metadata commit
	conn := storeconn.New(docs, meta)

	err := conn.AddDocumentVersion(ctx, docID, userID, "add b",
		func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
			return &docdb.CreateVersionResult{
				Version:    newVersion,
				WriteFiles: []fs.FileReader{fs.NewMemFile("b.txt", []byte("b content"))},
			}, nil
		},
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)

	// The panic reaches the caller as an error carrying its value, not as a panic.
	require.ErrorContains(t, err, "document store blew up")
	require.Equal(t, []docdb.VersionTime{newVersion}, meta.deletedVersions,
		"the version committed before the panic must be rolled back")
	require.NotContains(t, meta.stored, newVersion)
}

// TestConn_CreateDocument_RollbackDeletesOrphanedBlobs verifies that when
// creating a genesis document fails after the blobs were written (here the
// metadata insert fails), the rollback deletes the just-written blobs instead
// of orphaning them. The existence guard proved the document was new, so the
// rollback deletes the whole document's blobs — which also cleans up a partial
// blob write that returned no FileInfos.
func TestConn_CreateDocument_RollbackDeletesOrphanedBlobs(t *testing.T) {
	ctx := context.Background()
	docID := uu.IDv4()
	companyID := uu.IDv4()
	userID := uu.IDv4()
	content := []byte("genesis content")

	meta := newFakeMetadataStore()
	meta.createVersionErr = errors.New("metadata insert failed")
	docs := newFakeDocumentStore() // CreateDocumentVersion succeeds (writes the blob)
	conn := storeconn.New(docs, meta)

	err := conn.CreateDocument(ctx, companyID, docID, userID, "genesis",
		docdb.NewVersionTime(),
		[]fs.FileReader{fs.NewMemFile("a.txt", content)},
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)

	require.Error(t, err) // the failure surfaces to the caller
	require.Positive(t, docs.deleteDocumentCalls,
		"rollback must delete the blobs written before the metadata insert failed")
	// The metadata insert never succeeded (versionInfo is nil), so the surgical
	// metadata rollback must not run — there is nothing this call inserted.
	require.Empty(t, meta.deletedVersions, "must not delete metadata when nothing was inserted")
}

// TestConn_CreateDocument_RollsBackOnPanic verifies that a panic from a store or
// from onNewVersion is converted into an error first, so the rollback that only
// runs on an error actually runs.
//
// CreateDocument looked like it already did this, but its
// errs.RecoverPanicAsErrorWithFuncParams sat inside the rollback closure, where
// recover returns nil: a deferred function only recovers when it calls recover
// itself. The panic escaped with the half-created document left behind.
func TestConn_CreateDocument_RollsBackOnPanic(t *testing.T) {
	version := docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")

	t.Run("metadata store panics after the blobs were written", func(t *testing.T) {
		docID := uu.IDv4()
		meta := newFakeMetadataStore()
		meta.panicOnCreateVersion = true
		docs := newFakeDocumentStore()
		conn := storeconn.New(docs, meta)

		err := conn.CreateDocument(context.Background(), uu.IDv4(), docID, uu.IDv4(), "genesis",
			version,
			[]fs.FileReader{fs.NewMemFile("a.txt", []byte("genesis content"))},
			func(context.Context, *docdb.VersionInfo) error { return nil },
		)

		require.ErrorContains(t, err, "metadata store blew up")
		require.Positive(t, docs.deleteDocumentCalls, "the written blobs must be deleted")
		require.Empty(t, docs.stored, "no orphaned blob may be left behind")
		// Nothing was inserted, so there is no metadata version to remove.
		require.Empty(t, meta.deletedVersions)
	})

	t.Run("onNewVersion panics after the metadata version was committed", func(t *testing.T) {
		docID := uu.IDv4()
		meta := newFakeMetadataStore()
		docs := newFakeDocumentStore()
		conn := storeconn.New(docs, meta)

		err := conn.CreateDocument(context.Background(), uu.IDv4(), docID, uu.IDv4(), "genesis",
			version,
			[]fs.FileReader{fs.NewMemFile("a.txt", []byte("genesis content"))},
			func(context.Context, *docdb.VersionInfo) error { panic("onNewVersion blew up") },
		)

		require.ErrorContains(t, err, "onNewVersion blew up")
		require.Positive(t, docs.deleteDocumentCalls, "the written blobs must be deleted")
		require.Equal(t, []docdb.VersionTime{version}, meta.deletedVersions,
			"the committed metadata version must be rolled back, and only that one")
	})
}

// TestConn_CreateDocument_RollbackDeletesOnlyCreatedVersion verifies that when a
// genesis create fails AFTER its metadata version was committed (here
// onNewVersion fails), the rollback deletes exactly that one version via
// DeleteDocumentVersion — not the whole document. The existence guard only
// checks the DocumentStore, so the document may already hold other versions in
// the MetadataStore; wiping the document would destroy them.
func TestConn_CreateDocument_RollbackDeletesOnlyCreatedVersion(t *testing.T) {
	ctx := context.Background()
	docID := uu.IDv4()
	companyID := uu.IDv4()
	userID := uu.IDv4()
	version := docdb.NewVersionTime()

	meta := newFakeMetadataStore() // CreateDocumentVersion succeeds (versionInfo != nil)
	docs := newFakeDocumentStore()
	conn := storeconn.New(docs, meta)

	err := conn.CreateDocument(ctx, companyID, docID, userID, "genesis",
		version,
		[]fs.FileReader{fs.NewMemFile("a.txt", []byte("genesis content"))},
		func(context.Context, *docdb.VersionInfo) error { return errors.New("onNewVersion rejected") },
	)

	require.Error(t, err)
	require.Equal(t, []docdb.VersionTime{version}, meta.deletedVersions,
		"rollback must target exactly the version this call created, not the whole document")
	require.Positive(t, docs.deleteDocumentCalls, "rollback must delete the written blobs")
}

// TestConn_CreateDocument_ExistingDocumentRefused verifies that creating a
// genesis document whose files already exist in the documentStore is refused
// with ErrDocumentAlreadyExists before anything is written, so the rollback
// (which deletes blobs and a metadata version) never runs.
func TestConn_CreateDocument_ExistingDocumentRefused(t *testing.T) {
	ctx := context.Background()
	docID := uu.IDv4()
	companyID := uu.IDv4()
	userID := uu.IDv4()

	meta := newFakeMetadataStore()
	// The document already exists: the store holds a file for it.
	docs := newFakeDocumentStore(docdb.FileInfo{Name: "a.txt", Hash: docdb.ContentHash([]byte("x"))})
	conn := storeconn.New(docs, meta)

	err := conn.CreateDocument(ctx, companyID, docID, userID, "genesis",
		docdb.NewVersionTime(),
		[]fs.FileReader{fs.NewMemFile("a.txt", []byte("x"))},
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)

	require.ErrorIs(t, err, docdb.NewErrDocumentAlreadyExists(docID))
	// The pre-existing document must be left untouched: no rollback at all.
	require.Zero(t, docs.deleteDocumentCalls, "must not delete blobs of an existing document")
	require.Empty(t, meta.deletedVersions, "must not delete metadata of an existing document")
}

// TestConn_CreateDocument_ConcurrentLoserKeepsWinnerBlobs verifies that when a
// genesis create loses a concurrent race — its blobs were written but the
// metadata insert failed with ErrDocumentAlreadyExists because another writer
// already holds the genesis version — the rollback does NOT delete the blobs.
// Those objects are content-addressed and shared with the winner, so deleting
// them would corrupt the winning document.
func TestConn_CreateDocument_ConcurrentLoserKeepsWinnerBlobs(t *testing.T) {
	ctx := context.Background()
	docID := uu.IDv4()
	companyID := uu.IDv4()
	userID := uu.IDv4()

	meta := newFakeMetadataStore()
	// The winner already committed the genesis version; this loser's insert
	// hits the one-genesis-per-document unique index.
	meta.createVersionErr = docdb.NewErrDocumentAlreadyExists(docID)
	docs := newFakeDocumentStore() // CreateDocumentVersion succeeds (writes the shared blob)
	conn := storeconn.New(docs, meta)

	err := conn.CreateDocument(ctx, companyID, docID, userID, "genesis",
		docdb.NewVersionTime(),
		[]fs.FileReader{fs.NewMemFile("a.txt", []byte("genesis content"))},
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)

	require.ErrorIs(t, err, docdb.NewErrDocumentAlreadyExists(docID))
	// The winner owns the (identical, content-addressed) blobs: the loser must
	// not delete them, and never inserted metadata to roll back either.
	require.Zero(t, docs.deleteDocumentCalls,
		"loser must not delete the winner's shared content-addressed blobs")
	require.Empty(t, meta.deletedVersions, "must not delete metadata when nothing was inserted")
}

// TestConn_CreateDocument_RollbackIgnoresNotFound verifies that when a genesis
// create fails before any blob is written, the blob rollback's DeleteDocument
// returning ErrDocumentNotFound (nothing to delete) is not joined onto the real
// cause: the returned error must report the actual failure and must not
// spuriously match ErrDocumentNotFound / os.ErrNotExist.
func TestConn_CreateDocument_RollbackIgnoresNotFound(t *testing.T) {
	ctx := context.Background()
	docID := uu.IDv4()
	companyID := uu.IDv4()
	userID := uu.IDv4()

	meta := newFakeMetadataStore()
	// The blob write fails, so the store holds nothing and its DeleteDocument
	// answers the rollback with not-found.
	docs := newFakeDocumentStore()
	docs.createErr = errors.New("blob write failed")
	conn := storeconn.New(docs, meta)

	err := conn.CreateDocument(ctx, companyID, docID, userID, "genesis",
		docdb.NewVersionTime(),
		[]fs.FileReader{fs.NewMemFile("a.txt", []byte("genesis content"))},
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)

	require.Error(t, err)
	require.ErrorContains(t, err, "blob write failed")
	require.Positive(t, docs.deleteDocumentCalls) // the rollback still attempted cleanup
	// The spurious not-found from the rollback delete must not leak out.
	require.NotErrorIs(t, err, os.ErrNotExist)
}
