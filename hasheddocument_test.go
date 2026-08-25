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
	otherCompanyID := uu.IDv4()
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
			// Creating a version identical to its predecessor is refused where
			// versions are created (Conn.AddDocumentVersion returns
			// ErrNoChanges), but a store can hold one anyway: deleting the
			// middle of v0(F), v1(G), v2(F) leaves v0 and v2 adjacent with the
			// same files. Rejecting it here would not undo it — RestoreDocument
			// validates first, so it would only make that document impossible
			// to back up, sync or migrate for good.
			name: "identical consecutive versions are valid so a stored document stays backupable",
			doc: &HashedDocument{
				ID: validID, CompanyID: validCompanyID, HashedFiles: validHashedFiles(),
				Versions: map[VersionTime]*HashedVersion{
					validVersion:  {CommitUserID: uu.IDv4(), CommitReason: "init", FileHashes: map[string]string{"a.txt": hash}},
					validVersion2: {CommitUserID: uu.IDv4(), CommitReason: "no change", FileHashes: map[string]string{"a.txt": hash}},
				},
			},
		},
		{
			// The same for the move that SetDocumentCompanyID rewrote back: the
			// pure company-move version v1 named another company, the marker
			// move rewrote it to the one v0 already names, and the two versions
			// are now indistinguishable. That document must still be backupable.
			name: "identical consecutive versions with the same company are valid",
			doc: &HashedDocument{
				ID: validID, CompanyID: validCompanyID, HashedFiles: validHashedFiles(),
				Versions: map[VersionTime]*HashedVersion{
					validVersion:  {CompanyID: validCompanyID, CommitUserID: uu.IDv4(), CommitReason: "init", FileHashes: map[string]string{"a.txt": hash}},
					validVersion2: {CompanyID: validCompanyID, CommitUserID: uu.IDv4(), CommitReason: "moved back", FileHashes: map[string]string{"a.txt": hash}},
				},
			},
		},
		{
			// A document is moved between companies by a version that changes
			// nothing but the company.
			name: "identical consecutive versions with a company change are valid",
			doc: &HashedDocument{
				ID: validID, CompanyID: otherCompanyID, HashedFiles: validHashedFiles(),
				Versions: map[VersionTime]*HashedVersion{
					validVersion:  {CompanyID: validCompanyID, CommitUserID: uu.IDv4(), CommitReason: "init", FileHashes: map[string]string{"a.txt": hash}},
					validVersion2: {CompanyID: otherCompanyID, CommitUserID: uu.IDv4(), CommitReason: "moved to another company", FileHashes: map[string]string{"a.txt": hash}},
				},
			},
		},
		{
			// A document is owned by the company of its latest version, so a
			// backup that names another company as the document's current one
			// contradicts itself: restoring it into a store that derives the
			// owner from the latest version would file it under a different
			// company than one that keeps a separate owner marker.
			name: "latest version with another company than the document is invalid",
			doc: &HashedDocument{
				ID: validID, CompanyID: validCompanyID, HashedFiles: validHashedFiles(),
				Versions: map[VersionTime]*HashedVersion{
					validVersion:  {CommitUserID: uu.IDv4(), CommitReason: "init", FileHashes: map[string]string{"a.txt": hash}},
					validVersion2: {CompanyID: otherCompanyID, CommitUserID: uu.IDv4(), CommitReason: "moved", FileHashes: map[string]string{"a.txt": hash, "b.txt": hash}},
				},
			},
			wantErr:     true,
			errContains: "but the document has",
		},
		{
			// Versions before the latest one may name any company: that is the
			// history of a document that was moved.
			name: "earlier version with another company is valid",
			doc: &HashedDocument{
				ID: validID, CompanyID: validCompanyID, HashedFiles: validHashedFiles(),
				Versions: map[VersionTime]*HashedVersion{
					validVersion:  {CompanyID: otherCompanyID, CommitUserID: uu.IDv4(), CommitReason: "init", FileHashes: map[string]string{"a.txt": hash}},
					validVersion2: {CompanyID: validCompanyID, CommitUserID: uu.IDv4(), CommitReason: "moved back", FileHashes: map[string]string{"a.txt": hash, "b.txt": hash}},
				},
			},
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

// TestHashedDocument_NilReceiver pins the nil receiver contract of every
// *HashedDocument method: methods without an error result return the zero
// value, methods with one return an error. These are called while walking a
// backup, so a typed nil reaching them has to fail the one document instead of
// taking down the restore.
func TestHashedDocument_NilReceiver(t *testing.T) {
	var doc *HashedDocument
	v0 := MustVersionTimeFromString("2024-01-01_00-00-00.000")

	t.Run("VersionCompanyID returns uu.IDNil", func(t *testing.T) {
		require.Equal(t, uu.IDNil, doc.VersionCompanyID(v0))
	})

	t.Run("VersionTimes returns nil", func(t *testing.T) {
		require.Nil(t, doc.VersionTimes())
	})

	t.Run("VersionInfo returns an error", func(t *testing.T) {
		info, err := doc.VersionInfo(v0)
		require.Nil(t, info)
		require.ErrorContains(t, err, "nil HashedDocument")
	})

	t.Run("Validate returns an error", func(t *testing.T) {
		require.ErrorContains(t, doc.Validate(), "nil HashedDocument")
	})
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

// TestHashedDocument_VersionInfo_FileDeltas covers the change lists a restore
// derives from a backup. A HashedDocument stores only the file hashes per
// version, so the deltas are reconstructed by diffing against the predecessor
// — and the result must match what the source Conn recorded, because a restore
// into a store that already holds the metadata verifies them against it.
func TestHashedDocument_VersionInfo_FileDeltas(t *testing.T) {
	var (
		v0 = MustVersionTimeFromString("2024-01-01_00-00-00.000")
		v1 = MustVersionTimeFromString("2024-01-02_00-00-00.000")

		keepData = []byte("keep")
		goneData = []byte("gone")
		modData1 = []byte("mod one")
		modData2 = []byte("mod two")
		newData  = []byte("new")

		keepHash = ContentHash(keepData)
		goneHash = ContentHash(goneData)
		modHash1 = ContentHash(modData1)
		modHash2 = ContentHash(modData2)
		newHash  = ContentHash(newData)
	)

	doc := &HashedDocument{
		ID:        uu.IDv4(),
		CompanyID: uu.IDv4(),
		HashedFiles: map[string][]byte{
			keepHash: keepData,
			goneHash: goneData,
			modHash1: modData1,
			modHash2: modData2,
			newHash:  newData,
		},
		Versions: map[VersionTime]*HashedVersion{
			v0: {CommitReason: "init", FileHashes: map[string]string{
				"keep.txt": keepHash,
				"gone.txt": goneHash,
				"mod.txt":  modHash1,
			}},
			v1: {CommitReason: "update", FileHashes: map[string]string{
				"keep.txt": keepHash,
				"mod.txt":  modHash2,
				"new.txt":  newHash,
			}},
		},
	}

	info, err := doc.VersionInfo(v1)
	require.NoError(t, err)
	require.NotNil(t, info.PrevVersion)
	require.True(t, info.PrevVersion.Equal(v0))
	require.Equal(t, []string{"new.txt"}, info.AddedFiles)
	require.Equal(t, []string{"mod.txt"}, info.ModifiedFiles)
	require.Equal(t, []string{"gone.txt"}, info.RemovedFiles)
	// Files stays the complete file set of the version, not just the changes.
	require.Equal(t,
		map[string]FileInfo{
			"keep.txt": {Name: "keep.txt", Size: int64(len(keepData)), Hash: keepHash},
			"mod.txt":  {Name: "mod.txt", Size: int64(len(modData2)), Hash: modHash2},
			"new.txt":  {Name: "new.txt", Size: int64(len(newData)), Hash: newHash},
		},
		info.Files,
	)
}

// TestHashedDocument_MovedBetweenCompanies covers the per-version company of a
// document that was moved between companies. A move is committed as a new
// version naming the new company, so a backup has to carry the company of every
// version: restoring one that files every version under the document's current
// company erases the move from the document's history, and makes the restored
// metadata differ from what the source recorded — which a store that verifies
// already stored versions against a restore rejects.
func TestHashedDocument_MovedBetweenCompanies(t *testing.T) {
	var (
		v0 = MustVersionTimeFromString("2024-01-01_00-00-00.000")
		v1 = MustVersionTimeFromString("2024-01-02_00-00-00.000")
		v2 = MustVersionTimeFromString("2024-01-03_00-00-00.000")

		data     = []byte("hello")
		hash     = ContentHash(data)
		moreData = []byte("more")
		moreHash = ContentHash(moreData)

		prevCompanyID = uu.IDv4()
		companyID     = uu.IDv4()

		doc = &HashedDocument{
			ID:          uu.IDv4(),
			CompanyID:   companyID,
			HashedFiles: map[string][]byte{hash: data, moreHash: moreData},
			Versions: map[VersionTime]*HashedVersion{
				// Committed before the move, under the previous company.
				v0: {CompanyID: prevCompanyID, CommitUserID: uu.IDv4(), CommitReason: "init", FileHashes: map[string]string{"a.txt": hash}},
				// The move: same files, new company.
				v1: {CompanyID: companyID, CommitUserID: uu.IDv4(), CommitReason: "moved to another company", FileHashes: map[string]string{"a.txt": hash}},
				// Committed after the move, company left unset to inherit.
				v2: {CommitUserID: uu.IDv4(), CommitReason: "added a file", FileHashes: map[string]string{"a.txt": hash, "b.txt": moreHash}},
			},
		}
	)

	require.NoError(t, doc.Validate())

	t.Run("VersionCompanyID reports the company of each version", func(t *testing.T) {
		require.Equal(t, prevCompanyID, doc.VersionCompanyID(v0))
		require.Equal(t, companyID, doc.VersionCompanyID(v1))
		// An unset version company inherits the document's company.
		require.Equal(t, companyID, doc.VersionCompanyID(v2))
	})

	t.Run("VersionInfo carries the company of the version", func(t *testing.T) {
		for _, tt := range []struct {
			version   VersionTime
			companyID uu.ID
		}{
			{v0, prevCompanyID},
			{v1, companyID},
			{v2, companyID},
		} {
			info, err := doc.VersionInfo(tt.version)
			require.NoError(t, err)
			require.Equal(t, tt.companyID, info.CompanyID, "company of version %s", tt.version)
		}
	})

	t.Run("CheckRestoreCompanyID compares at the latest version of the destination", func(t *testing.T) {
		// A destination that stopped before the move is owned by the previous
		// company: restoring the move into it is the point of the restore, not
		// a mismatch.
		require.NoError(t, CheckRestoreCompanyID(doc, []VersionTime{v0}, prevCompanyID))
		// The same destination owned by the company of a version it does not
		// have is a document of another company under the same ID.
		require.Error(t, CheckRestoreCompanyID(doc, []VersionTime{v0}, companyID))
		// A destination that has the move is owned by the new company.
		require.NoError(t, CheckRestoreCompanyID(doc, []VersionTime{v0, v1}, companyID))
		require.Error(t, CheckRestoreCompanyID(doc, []VersionTime{v0, v1}, prevCompanyID))
		// A version the backup does not have falls back to the document's
		// current company.
		require.NoError(t, CheckRestoreCompanyID(doc, []VersionTime{MustVersionTimeFromString("2030-01-01_00-00-00.000")}, companyID))
	})
}

// TestReadHashedDocument_MovedBetweenCompanies covers that a backup keeps the
// company every version was committed with, and that the latest version is read
// as owned by the company the Conn reports for the document: an implementation
// with a separate owner marker can have that marker point at a company its
// latest version does not name (SetDocumentCompanyID moves the marker without
// committing a version), while an implementation without such a marker derives
// the owner from the latest version — so the two would disagree about who owns
// the restored document.
func TestReadHashedDocument_MovedBetweenCompanies(t *testing.T) {
	ctx := context.Background()
	docID := uu.IDv4()
	prevCompanyID := uu.IDv4()
	companyID := uu.IDv4()
	markerCompanyID := uu.IDv4()

	v0 := MustVersionTimeFromString("2024-01-01_00-00-00.000")
	v1 := MustVersionTimeFromString("2024-01-02_00-00-00.000")

	data := []byte("hello world")
	info := FileInfo{Name: "a.txt", Size: int64(len(data)), Hash: ContentHash(data)}

	// newMock serves two versions committed under prevCompanyID and companyID
	// while reporting docCompanyID as the document's company.
	newMock := func(docCompanyID uu.ID) *MockConn {
		return &MockConn{
			DocumentCompanyIDMock: func(context.Context, uu.ID) (uu.ID, error) {
				return docCompanyID, nil
			},
			DocumentVersionsMock: func(context.Context, uu.ID) ([]VersionTime, error) {
				return []VersionTime{v0, v1}, nil
			},
			DocumentVersionInfoMock: func(_ context.Context, _ uu.ID, version VersionTime) (*VersionInfo, error) {
				versionCompanyID := prevCompanyID
				if version.Equal(v1) {
					versionCompanyID = companyID
				}
				return &VersionInfo{
					CompanyID: versionCompanyID,
					DocID:     docID,
					Version:   version,
					Files:     map[string]FileInfo{"a.txt": info},
				}, nil
			},
			DocumentVersionFileProviderMock: func(context.Context, uu.ID, VersionTime) (FileProvider, error) {
				return NewFileProvider(fs.NewMemFile("a.txt", data)), nil
			},
		}
	}

	t.Run("every version keeps the company it was committed with", func(t *testing.T) {
		doc, err := ReadHashedDocument(ctx, newMock(companyID), docID)
		require.NoError(t, err)
		require.NoError(t, doc.Validate())
		require.Equal(t, companyID, doc.CompanyID)
		require.Equal(t, prevCompanyID, doc.VersionCompanyID(v0))
		require.Equal(t, companyID, doc.VersionCompanyID(v1))
	})

	t.Run("the latest version is owned by the company the Conn reports", func(t *testing.T) {
		doc, err := ReadHashedDocument(ctx, newMock(markerCompanyID), docID)
		require.NoError(t, err)
		// The backup must be restorable, which requires the document and its
		// latest version to name the same company.
		require.NoError(t, doc.Validate())
		require.Equal(t, markerCompanyID, doc.CompanyID)
		require.Equal(t, markerCompanyID, doc.VersionCompanyID(v1))
		// Versions before the latest one keep what they recorded.
		require.Equal(t, prevCompanyID, doc.VersionCompanyID(v0))
	})
}

// TestHashedDocumentValidateRejectsInvalidVersionCompanyID covers a per-version
// company that is set but malformed.
//
// uu.IDNil means the version inherits the document's company, so it is the one
// value that must stay accepted. Any other value is persisted by both restore
// implementations as committed history, and localfsdb files a document under a
// directory named after it — which the company enumeration then cannot parse.
func TestHashedDocumentValidateRejectsInvalidVersionCompanyID(t *testing.T) {
	companyID := uu.IDv4()
	docID := uu.IDv4()
	data := []byte("content of a")
	hash := ContentHash(data)
	v0 := MustVersionTimeFromString("2024-01-01_00-00-00.000")

	newDoc := func(versionCompanyID uu.ID) *HashedDocument {
		return &HashedDocument{
			ID:          docID,
			CompanyID:   companyID,
			HashedFiles: map[string][]byte{hash: data},
			Versions: map[VersionTime]*HashedVersion{
				v0: {
					CompanyID:    versionCompanyID,
					CommitUserID: uu.IDv4(),
					CommitReason: "initial",
					FileHashes:   map[string]string{"a.txt": hash},
				},
			},
		}
	}

	// unset inherits the document's company and stays valid
	require.NoError(t, newDoc(uu.IDNil).Validate())
	// the document's own company named explicitly is valid
	require.NoError(t, newDoc(companyID).Validate())
	// a set but malformed company is not
	require.ErrorContains(t, newDoc(uu.ID{0x01}).Validate(), "invalid CompanyID")
}
