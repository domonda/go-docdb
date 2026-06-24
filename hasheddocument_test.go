package docdb

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

// TestReadHashedDocument_StorageMetadataMismatch covers the integrity checks
// that ReadHashedDocument performs between the files reported by the version
// FileProvider (storage) and the files tracked in VersionInfo (metadata).
func TestReadHashedDocument_StorageMetadataMismatch(t *testing.T) {
	ctx := context.Background()
	docID := uu.IDv4()
	companyID := uu.IDv4()
	version := MustVersionTimeFromString("2024-01-01_00-00-00.000")

	data := []byte("hello world")
	goodInfo := FileInfo{Name: "a.txt", Size: int64(len(data)), Hash: ContentHash(data)}

	// newMock builds a Conn serving a single version whose storage files are
	// providerFiles and whose tracked metadata is infoFiles.
	newMock := func(providerFiles []fs.FileReader, infoFiles map[string]FileInfo) *MockConn {
		return &MockConn{
			DocumentCompanyIDMock: func(context.Context, uu.ID) (uu.ID, error) {
				return companyID, nil
			},
			DocumentVersionsMock: func(context.Context, uu.ID) ([]VersionTime, error) {
				return []VersionTime{version}, nil
			},
			DocumentVersionInfoMock: func(context.Context, uu.ID, VersionTime) (*VersionInfo, error) {
				return &VersionInfo{
					CompanyID: companyID,
					DocID:     docID,
					Version:   version,
					Files:     infoFiles,
				}, nil
			},
			DocumentVersionFileProviderMock: func(context.Context, uu.ID, VersionTime) (FileProvider, error) {
				return NewFileProvider(providerFiles...), nil
			},
		}
	}

	t.Run("valid document", func(t *testing.T) {
		conn := newMock(
			[]fs.FileReader{fs.NewMemFile("a.txt", data)},
			map[string]FileInfo{"a.txt": goodInfo},
		)
		doc, err := ReadHashedDocument(ctx, conn, docID)
		require.NoError(t, err)
		require.Equal(t, companyID, doc.CompanyID)
		require.Len(t, doc.Versions, 1)
		require.Equal(t, goodInfo.Hash, doc.Versions[version].FileHashes["a.txt"])
		require.Equal(t, data, doc.HashedFiles[goodInfo.Hash])
	})

	t.Run("file in storage but untracked in version info", func(t *testing.T) {
		conn := newMock(
			[]fs.FileReader{fs.NewMemFile("a.txt", data), fs.NewMemFile("extra.txt", []byte("x"))},
			map[string]FileInfo{"a.txt": goodInfo},
		)
		_, err := ReadHashedDocument(ctx, conn, docID)
		require.ErrorContains(t, err, "not tracked in version info")
	})

	t.Run("file size mismatch", func(t *testing.T) {
		conn := newMock(
			[]fs.FileReader{fs.NewMemFile("a.txt", data)},
			map[string]FileInfo{"a.txt": {Name: "a.txt", Size: goodInfo.Size + 100, Hash: goodInfo.Hash}},
		)
		_, err := ReadHashedDocument(ctx, conn, docID)
		require.ErrorContains(t, err, "bytes")
	})

	t.Run("file content hash mismatch", func(t *testing.T) {
		wrongHash := ContentHash([]byte("different content"))
		conn := newMock(
			[]fs.FileReader{fs.NewMemFile("a.txt", data)},
			map[string]FileInfo{"a.txt": {Name: "a.txt", Size: goodInfo.Size, Hash: wrongHash}},
		)
		_, err := ReadHashedDocument(ctx, conn, docID)
		require.ErrorContains(t, err, "hash")
	})

	t.Run("file tracked in version info but missing from storage", func(t *testing.T) {
		conn := newMock(
			[]fs.FileReader{fs.NewMemFile("a.txt", data)},
			map[string]FileInfo{
				"a.txt":       goodInfo,
				"missing.txt": {Name: "missing.txt", Size: 1, Hash: ContentHash([]byte("z"))},
			},
		)
		_, err := ReadHashedDocument(ctx, conn, docID)
		require.ErrorContains(t, err, "missing from storage")
	})
}

// TestHashedDocument_Validate covers every branch of HashedDocument.Validate.
func TestHashedDocument_Validate(t *testing.T) {
	validID := uu.IDv4()
	validCompanyID := uu.IDv4()
	validVersion := MustVersionTimeFromString("2024-01-01_00-00-00.000")
	validVersion2 := MustVersionTimeFromString("2024-01-01_00-00-00.001")
	var zeroVersion VersionTime

	data := []byte("hello")
	hash := ContentHash(data)
	validHashedFiles := func() map[string][]byte { return map[string][]byte{hash: data} }
	validVersions := func() map[VersionTime]*HashedVersion {
		return map[VersionTime]*HashedVersion{
			validVersion: {CommitUserID: uu.IDv4(), CommitReason: "init", FileHashes: map[string]string{"a.txt": hash}},
		}
	}

	tests := []struct {
		name        string
		doc         *HashedDocument
		wantErr     bool
		errContains string
	}{
		{
			name: "valid",
			doc:  &HashedDocument{ID: validID, CompanyID: validCompanyID, HashedFiles: validHashedFiles(), Versions: validVersions()},
		},
		{
			name:        "nil receiver",
			doc:         nil,
			wantErr:     true,
			errContains: "nil HashedDocument",
		},
		{
			name:        "invalid ID",
			doc:         &HashedDocument{ID: uu.IDNil, CompanyID: validCompanyID, HashedFiles: validHashedFiles(), Versions: validVersions()},
			wantErr:     true,
			errContains: "ID is invalid",
		},
		{
			name:        "invalid CompanyID",
			doc:         &HashedDocument{ID: validID, CompanyID: uu.IDNil, HashedFiles: validHashedFiles(), Versions: validVersions()},
			wantErr:     true,
			errContains: "CompanyID is invalid",
		},
		{
			name:        "no versions",
			doc:         &HashedDocument{ID: validID, CompanyID: validCompanyID, HashedFiles: validHashedFiles(), Versions: nil},
			wantErr:     true,
			errContains: "no versions",
		},
		{
			// The first version of a document cannot be empty.
			name: "first version with no files is invalid",
			doc: &HashedDocument{
				ID: validID, CompanyID: validCompanyID, HashedFiles: map[string][]byte{},
				Versions: map[VersionTime]*HashedVersion{
					validVersion: {CommitUserID: uu.IDv4(), CommitReason: "init", FileHashes: map[string]string{}},
				},
			},
			wantErr:     true,
			errContains: "has no files",
		},
		{
			// No version may remove all files: a later version with no files is
			// invalid, not just the first one.
			name: "later version with no files is invalid",
			doc: &HashedDocument{
				ID: validID, CompanyID: validCompanyID, HashedFiles: validHashedFiles(),
				Versions: map[VersionTime]*HashedVersion{
					validVersion:  {CommitUserID: uu.IDv4(), CommitReason: "init", FileHashes: map[string]string{"a.txt": hash}},
					validVersion2: {CommitUserID: uu.IDv4(), CommitReason: "removed all files", FileHashes: map[string]string{}},
				},
			},
			wantErr:     true,
			errContains: "has no files",
		},
		{
			// Two consecutive versions with identical files are a change-less
			// version, which must not exist.
			name: "identical consecutive versions are invalid",
			doc: &HashedDocument{
				ID: validID, CompanyID: validCompanyID, HashedFiles: validHashedFiles(),
				Versions: map[VersionTime]*HashedVersion{
					validVersion:  {CommitUserID: uu.IDv4(), CommitReason: "init", FileHashes: map[string]string{"a.txt": hash}},
					validVersion2: {CommitUserID: uu.IDv4(), CommitReason: "no change", FileHashes: map[string]string{"a.txt": hash}},
				},
			},
			wantErr:     true,
			errContains: "no change",
		},
		{
			name: "invalid version time",
			doc: &HashedDocument{
				ID: validID, CompanyID: validCompanyID, HashedFiles: validHashedFiles(),
				Versions: map[VersionTime]*HashedVersion{zeroVersion: {FileHashes: map[string]string{}}},
			},
			wantErr:     true,
			errContains: "is invalid",
		},
		{
			name: "nil HashedVersion",
			doc: &HashedDocument{
				ID: validID, CompanyID: validCompanyID, HashedFiles: validHashedFiles(),
				Versions: map[VersionTime]*HashedVersion{validVersion: nil},
			},
			wantErr:     true,
			errContains: "nil HashedVersion",
		},
		{
			name: "file references missing hash",
			doc: &HashedDocument{
				ID: validID, CompanyID: validCompanyID, HashedFiles: map[string][]byte{},
				Versions: map[VersionTime]*HashedVersion{
					validVersion: {FileHashes: map[string]string{"a.txt": "0000000000000000000000000000000000000000000000000000000000000000"}},
				},
			},
			wantErr:     true,
			errContains: "references missing hash",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.doc.Validate()
			if !tt.wantErr {
				require.NoError(t, err)
				return
			}
			require.Error(t, err)
			require.ErrorContains(t, err, tt.errContains)
		})
	}
}

func TestHashedDocument_VersionInfo(t *testing.T) {
	v0 := MustVersionTimeFromString("2024-01-01_00-00-00.000")
	data := []byte("hello")
	hash := ContentHash(data)

	doc := &HashedDocument{
		ID:          uu.IDv4(),
		CompanyID:   uu.IDv4(),
		HashedFiles: map[string][]byte{hash: data},
		Versions: map[VersionTime]*HashedVersion{
			v0: {CommitUserID: uu.IDv4(), CommitReason: "init", FileHashes: map[string]string{"a.txt": hash}},
		},
	}

	t.Run("valid version", func(t *testing.T) {
		info, err := doc.VersionInfo(v0)
		require.NoError(t, err)
		require.NotNil(t, info)
		require.Nil(t, info.PrevVersion)
		require.Equal(t, []string{"a.txt"}, info.AddedFiles)
	})

	t.Run("unknown version returns ErrDocumentVersionNotFound", func(t *testing.T) {
		info, err := doc.VersionInfo(MustVersionTimeFromString("2030-01-01_00-00-00.000"))
		require.Nil(t, info)
		require.True(t, errs.Has[ErrDocumentVersionNotFound](err))
	})

	t.Run("inconsistent document returns a non-not-found error", func(t *testing.T) {
		bad := &HashedDocument{
			ID:          uu.IDv4(),
			CompanyID:   uu.IDv4(),
			HashedFiles: map[string][]byte{}, // referenced hash is absent
			Versions: map[VersionTime]*HashedVersion{
				v0: {FileHashes: map[string]string{"a.txt": hash}},
			},
		}
		require.NotPanics(t, func() {
			info, err := bad.VersionInfo(v0)
			require.Nil(t, info)
			// Corruption must be reported as an error and be distinguishable
			// from a merely missing version.
			require.Error(t, err)
			require.False(t, errs.Has[ErrDocumentVersionNotFound](err))
		})
	})
}
