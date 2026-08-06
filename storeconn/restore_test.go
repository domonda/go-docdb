package storeconn_test

import (
	"context"
	"errors"
	"maps"
	"slices"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/storeconn"
)

// restoreDocumentStore is a content-addressed in-memory storeconn.DocumentStore:
// it holds files by name and content hash and knows nothing about versions, like
// the S3 store it models. Only the methods a merge-restore uses are implemented;
// any other is promoted from the embedded nil interface and panics if called.
type restoreDocumentStore struct {
	storeconn.DocumentStore

	stored map[docdb.FileInfo]struct{} // (Name, Hash) of every stored file

	writtenVersions   []docdb.VersionTime // versions passed to CreateDocumentVersion
	filesExistCalls   int                 // calls to DocumentHashFilesExist
	filesExistChecked int                 // files asked about in total

	// failWriteOf, when set, makes CreateDocumentVersion fail for that version,
	// modelling a blob write that dies mid-restore.
	failWriteOf *docdb.VersionTime

	deleteDocumentCalls int
	deletedHashes       []string
}

func newRestoreDocumentStore(files ...docdb.FileInfo) *restoreDocumentStore {
	store := &restoreDocumentStore{stored: make(map[docdb.FileInfo]struct{})}
	for _, file := range files {
		store.stored[file] = struct{}{}
	}
	return store
}

func (d *restoreDocumentStore) DocumentExists(context.Context, uu.ID) (bool, error) {
	return len(d.stored) > 0, nil
}

func (d *restoreDocumentStore) DocumentHashFilesExist(_ context.Context, _ uu.ID, files []docdb.FileInfo) (map[docdb.FileInfo]bool, error) {
	d.filesExistCalls++
	d.filesExistChecked += len(files)
	exist := make(map[docdb.FileInfo]bool, len(files))
	for _, file := range files {
		_, exist[file] = d.stored[file]
	}
	return exist, nil
}

func (d *restoreDocumentStore) DeleteDocument(context.Context, uu.ID) error {
	d.deleteDocumentCalls++
	clear(d.stored)
	return nil
}

func (d *restoreDocumentStore) DeleteDocumentHashes(_ context.Context, _ uu.ID, hashes []string) error {
	d.deletedHashes = append(d.deletedHashes, hashes...)
	for file := range d.stored {
		if slices.Contains(hashes, file.Hash) {
			delete(d.stored, file)
		}
	}
	return nil
}

func (d *restoreDocumentStore) CreateDocumentVersion(_ context.Context, _ uu.ID, version docdb.VersionTime, files []fs.FileReader) ([]*docdb.FileInfo, error) {
	if d.failWriteOf != nil && d.failWriteOf.Equal(version) {
		return nil, errors.New("blob write failed")
	}
	d.writtenVersions = append(d.writtenVersions, version)
	fileInfos := make([]*docdb.FileInfo, len(files))
	for i, file := range files {
		data, err := file.ReadAll()
		if err != nil {
			return nil, err
		}
		info := docdb.FileInfo{Name: file.Name(), Hash: docdb.ContentHash(data)}
		d.stored[info] = struct{}{}
		fileInfos[i] = &docdb.FileInfo{Name: info.Name, Size: int64(len(data)), Hash: info.Hash}
	}
	return fileInfos, nil
}

// has reports whether every file of the version is stored.
func (d *restoreDocumentStore) has(doc *docdb.HashedDocument, version docdb.VersionTime) bool {
	for filename, hash := range doc.Versions[version].FileHashes {
		if _, ok := d.stored[docdb.FileInfo{Name: filename, Hash: hash}]; !ok {
			return false
		}
	}
	return true
}

// restoreMetadataStore is a storeconn.MetadataStore that already holds every
// version of the document, which is the state a migration into a shared
// MetadataStore starts from: the version rows were mirrored long before any file
// content was copied.
type restoreMetadataStore struct {
	storeconn.MetadataStore

	companyID uu.ID
	// stored is the version metadata the store already holds, keyed by version.
	stored map[docdb.VersionTime]*docdb.VersionInfo

	// versionsExist models pgstore.ContextWithMetadataStoreVersionsExist: the
	// store inserts nothing and verifies instead, so a create for an
	// already-stored version succeeds. When false the store really inserts and
	// rejects a duplicate the way Postgres does.
	versionsExist bool

	insertedVersions    []docdb.VersionTime
	deletedVersions     []docdb.VersionTime
	deleteDocumentCalls int
}

// newRestoreMetadataStore returns a MetadataStore already holding the passed
// versions of doc, exactly as the backup describes them — the state a migration
// starts from, where the version rows were mirrored long before any file
// content was copied.
func newRestoreMetadataStore(t *testing.T, doc *docdb.HashedDocument, versions ...docdb.VersionTime) *restoreMetadataStore {
	t.Helper()
	store := &restoreMetadataStore{
		companyID: doc.CompanyID,
		stored:    make(map[docdb.VersionTime]*docdb.VersionInfo, len(versions)),
	}
	for _, v := range versions {
		info, err := doc.VersionInfo(v)
		require.NoError(t, err)
		store.stored[v] = info
	}
	return store
}

func (m *restoreMetadataStore) DocumentCompanyID(context.Context, uu.ID) (uu.ID, error) {
	return m.companyID, nil
}

func (m *restoreMetadataStore) DocumentVersions(_ context.Context, docID uu.ID) ([]docdb.VersionTime, error) {
	if len(m.stored) == 0 {
		// Same as pgstore: a document without versions is not found.
		return nil, docdb.NewErrDocumentNotFound(docID)
	}
	return slices.SortedFunc(maps.Keys(m.stored), docdb.VersionTime.Compare), nil
}

func (m *restoreMetadataStore) DocumentVersionInfo(_ context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error) {
	info, ok := m.stored[version]
	if !ok {
		return nil, docdb.NewErrDocumentVersionNotFound(docID, version)
	}
	return info, nil
}

func (m *restoreMetadataStore) DeleteDocument(context.Context, uu.ID) error {
	m.deleteDocumentCalls++
	clear(m.stored)
	return nil
}

func (m *restoreMetadataStore) DeleteDocumentVersion(_ context.Context, _ uu.ID, version docdb.VersionTime) ([]docdb.VersionTime, []string, error) {
	m.deletedVersions = append(m.deletedVersions, version)
	delete(m.stored, version)
	return slices.SortedFunc(maps.Keys(m.stored), docdb.VersionTime.Compare), nil, nil
}

func (m *restoreMetadataStore) CreateDocumentVersion(_ context.Context, in storeconn.CreateDocumentVersionInput) (*docdb.VersionInfo, error) {
	if stored, ok := m.stored[in.NewVersion]; ok {
		if m.versionsExist {
			return stored, nil
		}
		if in.PreviousVersion == nil {
			return nil, docdb.NewErrDocumentAlreadyExists(in.DocID)
		}
		return nil, docdb.NewErrVersionAlreadyExists(in.DocID, in.NewVersion)
	}
	m.stored[in.NewVersion] = &docdb.VersionInfo{
		DocID:     in.DocID,
		CompanyID: in.CompanyID,
		Version:   in.NewVersion,
		Files:     in.Files,
	}
	m.insertedVersions = append(m.insertedVersions, in.NewVersion)
	return m.stored[in.NewVersion], nil
}

// newRestoreTestDoc returns a two-version backup: v1 holds a.txt, v2 adds b.txt.
func newRestoreTestDoc(companyID, docID uu.ID) (doc *docdb.HashedDocument, v1, v2 docdb.VersionTime) {
	v1 = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
	v2 = docdb.MustVersionTimeFromString("2024-01-02_00-00-00.000")

	dataA := []byte("content of a")
	dataB := []byte("content of b")
	hashA := docdb.ContentHash(dataA)
	hashB := docdb.ContentHash(dataB)

	doc = &docdb.HashedDocument{
		ID:          docID,
		CompanyID:   companyID,
		HashedFiles: map[string][]byte{hashA: dataA, hashB: dataB},
		Versions: map[docdb.VersionTime]*docdb.HashedVersion{
			v1: {CommitUserID: uu.IDv4(), CommitReason: "initial", FileHashes: map[string]string{
				"a.txt": hashA,
			}},
			v2: {CommitUserID: uu.IDv4(), CommitReason: "add b", FileHashes: map[string]string{
				"a.txt": hashA,
				"b.txt": hashB,
			}},
		},
	}
	return doc, v1, v2
}

// TestConn_RestoreDocument_MergeResumesInterruptedCopy covers resuming a copy
// that was interrupted after some file content had been written.
//
// The MetadataStore already lists every version of the document — that is the
// premise of a migration into a shared MetadataStore — so the version list says
// nothing about what was copied. A merge-restore that skipped every version
// present there would return nil for a document whose later versions were never
// written, and the caller would count it as fully synced while the file store is
// missing files: silent data loss at cutover.
func TestConn_RestoreDocument_MergeResumesInterruptedCopy(t *testing.T) {
	companyID := uu.IDv4()
	docID := uu.IDv4()
	doc, v1, v2 := newRestoreTestDoc(companyID, docID)

	// Both modes must resume: the migration runs against a MetadataStore in
	// versions-exist mode, but a plain store that really inserts must not turn
	// the duplicate version into a failed restore either.
	for _, versionsExist := range []bool{true, false} {
		name := "versions-exist MetadataStore"
		if !versionsExist {
			name = "inserting MetadataStore"
		}
		t.Run(name, func(t *testing.T) {
			// The interrupted run got as far as v1's file.
			docs := newRestoreDocumentStore(docdb.FileInfo{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]})
			meta := newRestoreMetadataStore(t, doc, v1, v2)
			meta.versionsExist = versionsExist
			conn := storeconn.New(docs, meta)

			err := conn.RestoreDocument(t.Context(), doc, false)
			require.NoError(t, err)

			// Every file of every version must be in the DocumentStore now.
			require.True(t, docs.has(doc, v1), "files of v1 missing after restore")
			require.True(t, docs.has(doc, v2), "files of v2 missing after restore")

			// v1 was complete, so only v2 is written.
			require.Equal(t, []docdb.VersionTime{v2}, docs.writtenVersions)
			// Neither mode may add a version row: both already exist.
			require.Empty(t, meta.insertedVersions)
		})
	}
}

// TestConn_RestoreDocument_MergeSkipsFullyStoredDocument pins the common case:
// when both stores hold the whole document, nothing is written and the check
// costs a single DocumentStore round trip for the document, not one per version
// or per file.
func TestConn_RestoreDocument_MergeSkipsFullyStoredDocument(t *testing.T) {
	companyID := uu.IDv4()
	docID := uu.IDv4()
	doc, v1, v2 := newRestoreTestDoc(companyID, docID)

	docs := newRestoreDocumentStore(
		docdb.FileInfo{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]},
		docdb.FileInfo{Name: "b.txt", Hash: doc.Versions[v2].FileHashes["b.txt"]},
	)
	meta := newRestoreMetadataStore(t, doc, v1, v2)
	conn := storeconn.New(docs, meta)

	err := conn.RestoreDocument(t.Context(), doc, false)
	require.NoError(t, err)

	require.Empty(t, docs.writtenVersions, "a fully stored document must not be re-written")
	require.Empty(t, meta.insertedVersions)
	require.Equal(t, 1, docs.filesExistCalls, "the presence check must batch the whole document")
	// a.txt is shared by both versions and must only be asked about once.
	require.Equal(t, 2, docs.filesExistChecked)
}

// TestConn_RestoreDocument_MergeWritesVersionsMissingFromBothStores covers the
// ordinary merge case: a version the MetadataStore does not know is inserted and
// written, and one that is fully stored is left alone.
func TestConn_RestoreDocument_MergeWritesVersionsMissingFromBothStores(t *testing.T) {
	companyID := uu.IDv4()
	docID := uu.IDv4()
	doc, v1, v2 := newRestoreTestDoc(companyID, docID)

	docs := newRestoreDocumentStore(docdb.FileInfo{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]})
	meta := newRestoreMetadataStore(t, doc, v1)
	conn := storeconn.New(docs, meta)

	err := conn.RestoreDocument(t.Context(), doc, false)
	require.NoError(t, err)

	require.Equal(t, []docdb.VersionTime{v2}, docs.writtenVersions)
	require.Equal(t, []docdb.VersionTime{v2}, meta.insertedVersions)
	require.True(t, docs.has(doc, v2))
}

// TestConn_RestoreDocument_MergeIntoEmptyDocumentStore covers the start of a
// migration: the MetadataStore already holds every version, the DocumentStore
// holds nothing at all — either because the copy has not run yet or because it
// died before its first write.
//
// The document's existence in the DocumentStore says nothing about what the
// MetadataStore knows, so the versions must not be pushed through the genesis
// create path, which a store that really inserts refuses as a duplicate.
func TestConn_RestoreDocument_MergeIntoEmptyDocumentStore(t *testing.T) {
	companyID := uu.IDv4()
	docID := uu.IDv4()
	doc, v1, v2 := newRestoreTestDoc(companyID, docID)

	for _, versionsExist := range []bool{true, false} {
		name := "versions-exist MetadataStore"
		if !versionsExist {
			name = "inserting MetadataStore"
		}
		t.Run(name, func(t *testing.T) {
			docs := newRestoreDocumentStore() // nothing copied yet
			meta := newRestoreMetadataStore(t, doc, v1, v2)
			meta.versionsExist = versionsExist
			conn := storeconn.New(docs, meta)

			err := conn.RestoreDocument(t.Context(), doc, false)
			require.NoError(t, err)

			require.True(t, docs.has(doc, v1), "files of v1 missing after restore")
			require.True(t, docs.has(doc, v2), "files of v2 missing after restore")
			require.Equal(t, []docdb.VersionTime{v1, v2}, docs.writtenVersions)
			require.Empty(t, meta.insertedVersions, "both versions were already stored")
		})
	}
}

// TestConn_RestoreDocument_RollbackKeepsPreExistingVersions verifies that a
// failed restore only removes what it created. The MetadataStore may already
// hold versions of the document — that is the whole premise of restoring into a
// shared one — and those rows belong to whoever wrote them.
func TestConn_RestoreDocument_RollbackKeepsPreExistingVersions(t *testing.T) {
	companyID := uu.IDv4()
	docID := uu.IDv4()
	doc, v1, v2 := newRestoreTestDoc(companyID, docID)

	// The MetadataStore holds v2 but not v1, so the restore creates v1 (through
	// the genesis path, the DocumentStore being empty) and then fails writing
	// the files of the already-stored v2.
	docs := newRestoreDocumentStore()
	docs.failWriteOf = &v2
	meta := newRestoreMetadataStore(t, doc, v2)
	conn := storeconn.New(docs, meta)

	err := conn.RestoreDocument(t.Context(), doc, false)
	require.Error(t, err)

	require.Zero(t, meta.deleteDocumentCalls, "the rollback must not drop a document it did not create")
	require.Equal(t, []docdb.VersionTime{v1}, meta.deletedVersions, "only the created version is rolled back")
	require.Contains(t, meta.stored, v2, "the pre-existing version must survive the rollback")
}

// TestConn_RestoreDocument_MergeRejectsDifferentStoredFileSet covers a version
// whose files are missing from the DocumentStore and whose stored metadata does
// not describe the backup's version. The rejected insert is not the store
// confirming the backup — nothing of what would have been inserted was stored —
// so the file set is verified before its content is written under that version.
func TestConn_RestoreDocument_MergeRejectsDifferentStoredFileSet(t *testing.T) {
	companyID := uu.IDv4()
	docID := uu.IDv4()
	doc, v1, v2 := newRestoreTestDoc(companyID, docID)

	docs := newRestoreDocumentStore(docdb.FileInfo{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]})
	meta := newRestoreMetadataStore(t, doc, v1, v2)
	// The stored v2 describes a different file set than the backup's v2.
	meta.stored[v2] = &docdb.VersionInfo{
		DocID: docID, CompanyID: companyID, Version: v2,
		Files: map[string]docdb.FileInfo{
			"a.txt": {Name: "a.txt", Size: 1, Hash: docdb.ContentHash([]byte("something else"))},
		},
	}
	conn := storeconn.New(docs, meta)

	err := conn.RestoreDocument(t.Context(), doc, false)
	require.ErrorContains(t, err, "different file set")
	require.False(t, docs.has(doc, v2), "no file may be written under a version that is not the backup's")
}
