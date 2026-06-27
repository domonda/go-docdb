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

// fakeMetadataStore implements storeconn.MetadataStore for rollback tests.
// Only the methods exercised by AddDocumentVersion are implemented; any other
// method is promoted from the embedded nil interface and panics if called,
// which surfaces unexpected changes to the code path under test.
type fakeMetadataStore struct {
	storeconn.MetadataStore

	latest *docdb.VersionInfo

	addedVersion        docdb.VersionTime
	deleteVersionCalled bool
	// deletedVersion records the version passed to DeleteDocumentVersion, so a
	// test can assert the genesis rollback targets exactly the version it
	// created rather than wiping the whole document.
	deletedVersion docdb.VersionTime
	// createVersionErr, when set, is returned by CreateDocumentVersion to
	// simulate a metadata insert failure after the blobs were written.
	createVersionErr error
	// safeHashesToDelete models the sibling-safe set the real
	// DeleteDocumentVersion SQL returns: only hashes referenced solely by the
	// version being deleted (hashes still shared with a sibling are excluded).
	safeHashesToDelete []string
}

func (m *fakeMetadataStore) LatestDocumentVersionInfo(context.Context, uu.ID) (*docdb.VersionInfo, error) {
	return m.latest, nil
}

func (m *fakeMetadataStore) CreateDocumentVersion(_ context.Context, in storeconn.CreateDocumentVersionInput) (*docdb.VersionInfo, error) {
	if m.createVersionErr != nil {
		return nil, m.createVersionErr
	}
	m.addedVersion = in.NewVersion
	return &docdb.VersionInfo{DocID: in.DocID, CompanyID: in.CompanyID, Version: in.NewVersion}, nil
}

func (m *fakeMetadataStore) DeleteDocumentVersion(_ context.Context, _ uu.ID, version docdb.VersionTime) (leftVersions []docdb.VersionTime, hashesToDelete []string, err error) {
	m.deleteVersionCalled = true
	m.deletedVersion = version
	return nil, m.safeHashesToDelete, nil
}

// fakeDocumentStore implements storeconn.DocumentStore for rollback tests.
type fakeDocumentStore struct {
	storeconn.DocumentStore

	prevFiles []fs.FileReader
	createErr error
	// exists is returned by DocumentExists, which the genesis create path calls
	// to enforce the ErrDocumentAlreadyExists contract before writing anything.
	exists bool

	deletedHashes [][]string
	// deleteDocumentCalled records that the genesis rollback deleted the whole
	// document's blobs (the existence guard proved they were all written here).
	deleteDocumentCalled bool
	// deleteDocumentErr, when set, is returned by DeleteDocument to simulate the
	// blob rollback finding nothing to delete (ErrDocumentNotFound).
	deleteDocumentErr error
}

func (d *fakeDocumentStore) DocumentExists(context.Context, uu.ID) (bool, error) {
	return d.exists, nil
}

func (d *fakeDocumentStore) DeleteDocument(context.Context, uu.ID) error {
	d.deleteDocumentCalled = true
	return d.deleteDocumentErr
}

func (d *fakeDocumentStore) DocumentHashFileProvider(context.Context, uu.ID, []string) (docdb.FileProvider, error) {
	return docdb.NewFileProvider(d.prevFiles...), nil
}

func (d *fakeDocumentStore) CreateDocumentVersion(_ context.Context, _ uu.ID, _ docdb.VersionTime, files []fs.FileReader) ([]*docdb.FileInfo, error) {
	if d.createErr != nil {
		return nil, d.createErr
	}
	fileInfos := make([]*docdb.FileInfo, len(files))
	for i, file := range files {
		data, err := file.ReadAll()
		if err != nil {
			return nil, err
		}
		fileInfos[i] = &docdb.FileInfo{Name: file.Name(), Size: file.Size(), Hash: docdb.ContentHash(data)}
	}
	return fileInfos, nil
}

func (d *fakeDocumentStore) DeleteDocumentHashes(_ context.Context, _ uu.ID, hashes []string) error {
	d.deletedHashes = append(d.deletedHashes, hashes)
	return nil
}

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

			meta := &fakeMetadataStore{
				latest: &docdb.VersionInfo{
					DocID:     docID,
					CompanyID: companyID,
					Version:   v1,
					Files: map[string]docdb.FileInfo{
						"logo.png": {Name: "logo.png", Size: int64(len(content)), Hash: sharedHash},
					},
				},
				// logo.png in v1 still references sharedHash, so deleting the new
				// version reports nothing safe to delete.
				safeHashesToDelete: nil,
			}
			docs := &fakeDocumentStore{
				prevFiles: []fs.FileReader{fs.NewMemFile("logo.png", content)},
				createErr: tc.createErr,
			}
			conn := storeconn.New(docs, meta)

			// The new version adds icon.png with the same content as v1's
			// logo.png, so its added-file hash collides with a blob the sibling
			// version still uses.
			err := conn.AddDocumentVersion(ctx, docID, userID, "add icon",
				docdb.CreateVersionWriteFiles(fs.NewMemFile("icon.png", content)),
				tc.onNewVersion,
			)

			require.Error(t, err)                     // the failure surfaces to the caller
			require.True(t, meta.deleteVersionCalled) // the metadata version was rolled back
			for _, hashes := range docs.deletedHashes {
				require.NotContains(t, hashes, sharedHash,
					"rollback must not delete a blob whose hash is shared with a sibling version")
			}
		})
	}
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

	meta := &fakeMetadataStore{
		createVersionErr: errors.New("metadata insert failed"),
	}
	docs := &fakeDocumentStore{} // CreateDocumentVersion succeeds (writes the blob)
	conn := storeconn.New(docs, meta)

	err := conn.CreateDocument(ctx, companyID, docID, userID, "genesis",
		docdb.NewVersionTime(),
		[]fs.FileReader{fs.NewMemFile("a.txt", content)},
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)

	require.Error(t, err) // the failure surfaces to the caller
	require.True(t, docs.deleteDocumentCalled,
		"rollback must delete the blobs written before the metadata insert failed")
	// The metadata insert never succeeded (versionInfo is nil), so the surgical
	// metadata rollback must not run — there is nothing this call inserted.
	require.False(t, meta.deleteVersionCalled, "must not delete metadata when nothing was inserted")
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

	meta := &fakeMetadataStore{} // CreateDocumentVersion succeeds (versionInfo != nil)
	docs := &fakeDocumentStore{}
	conn := storeconn.New(docs, meta)

	err := conn.CreateDocument(ctx, companyID, docID, userID, "genesis",
		version,
		[]fs.FileReader{fs.NewMemFile("a.txt", []byte("genesis content"))},
		func(context.Context, *docdb.VersionInfo) error { return errors.New("onNewVersion rejected") },
	)

	require.Error(t, err)
	require.True(t, meta.deleteVersionCalled, "rollback must delete the committed metadata version")
	require.Equal(t, version, meta.deletedVersion,
		"rollback must target exactly the version this call created, not the whole document")
	require.True(t, docs.deleteDocumentCalled, "rollback must delete the written blobs")
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

	meta := &fakeMetadataStore{}
	docs := &fakeDocumentStore{exists: true} // the document already exists
	conn := storeconn.New(docs, meta)

	err := conn.CreateDocument(ctx, companyID, docID, userID, "genesis",
		docdb.NewVersionTime(),
		[]fs.FileReader{fs.NewMemFile("a.txt", []byte("x"))},
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)

	require.ErrorIs(t, err, docdb.NewErrDocumentAlreadyExists(docID))
	// The pre-existing document must be left untouched: no rollback at all.
	require.False(t, docs.deleteDocumentCalled, "must not delete blobs of an existing document")
	require.False(t, meta.deleteVersionCalled, "must not delete metadata of an existing document")
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

	meta := &fakeMetadataStore{
		// The winner already committed the genesis version; this loser's insert
		// hits the one-genesis-per-document unique index.
		createVersionErr: docdb.NewErrDocumentAlreadyExists(docID),
	}
	docs := &fakeDocumentStore{} // CreateDocumentVersion succeeds (writes the shared blob)
	conn := storeconn.New(docs, meta)

	err := conn.CreateDocument(ctx, companyID, docID, userID, "genesis",
		docdb.NewVersionTime(),
		[]fs.FileReader{fs.NewMemFile("a.txt", []byte("genesis content"))},
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)

	require.ErrorIs(t, err, docdb.NewErrDocumentAlreadyExists(docID))
	// The winner owns the (identical, content-addressed) blobs: the loser must
	// not delete them, and never inserted metadata to roll back either.
	require.False(t, docs.deleteDocumentCalled,
		"loser must not delete the winner's shared content-addressed blobs")
	require.False(t, meta.deleteVersionCalled, "must not delete metadata when nothing was inserted")
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

	meta := &fakeMetadataStore{}
	docs := &fakeDocumentStore{
		createErr:         errors.New("blob write failed"),
		deleteDocumentErr: docdb.NewErrDocumentNotFound(docID),
	}
	conn := storeconn.New(docs, meta)

	err := conn.CreateDocument(ctx, companyID, docID, userID, "genesis",
		docdb.NewVersionTime(),
		[]fs.FileReader{fs.NewMemFile("a.txt", []byte("genesis content"))},
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)

	require.Error(t, err)
	require.ErrorContains(t, err, "blob write failed")
	require.True(t, docs.deleteDocumentCalled) // the rollback still attempted cleanup
	// The spurious not-found from the rollback delete must not leak out.
	require.NotErrorIs(t, err, os.ErrNotExist)
}
