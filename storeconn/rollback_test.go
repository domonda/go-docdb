package storeconn_test

import (
	"context"
	"errors"
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
	// safeHashesToDelete models the sibling-safe set the real
	// DeleteDocumentVersion SQL returns: only hashes referenced solely by the
	// version being deleted (hashes still shared with a sibling are excluded).
	safeHashesToDelete []string
}

func (m *fakeMetadataStore) LatestDocumentVersionInfo(context.Context, uu.ID) (*docdb.VersionInfo, error) {
	return m.latest, nil
}

func (m *fakeMetadataStore) AddDocumentVersion(
	_ context.Context,
	newVersion, _ docdb.VersionTime,
	docID, companyID, _ uu.ID,
	_ string,
	_, _ []*docdb.FileInfo,
	_ []string,
) (*docdb.VersionInfo, error) {
	m.addedVersion = newVersion
	return &docdb.VersionInfo{DocID: docID, CompanyID: companyID, Version: newVersion}, nil
}

func (m *fakeMetadataStore) DeleteDocumentVersion(context.Context, uu.ID, docdb.VersionTime) (leftVersions []docdb.VersionTime, hashesToDelete []string, err error) {
	m.deleteVersionCalled = true
	return nil, m.safeHashesToDelete, nil
}

// fakeDocumentStore implements storeconn.DocumentStore for rollback tests.
type fakeDocumentStore struct {
	storeconn.DocumentStore

	prevFiles []fs.FileReader
	createErr error

	deletedHashes [][]string
}

func (d *fakeDocumentStore) DocumentHashFileProvider(context.Context, uu.ID, []string) (docdb.FileProvider, error) {
	return docdb.NewFileProvider(d.prevFiles...), nil
}

func (d *fakeDocumentStore) CreateDocument(context.Context, uu.ID, docdb.VersionTime, []fs.FileReader) error {
	return d.createErr
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
