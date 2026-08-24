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

// One fake per store interface, shared by every test in this package. Two of
// them per interface used to drift apart: adding a method to storeconn's
// DocumentStore or MetadataStore meant the same edit twice, and a test author
// had to know which of two fakes modelled which semantics.
//
// Only the methods the tests exercise are implemented; any other is promoted
// from the embedded nil interface and panics if called, which surfaces an
// unexpected change to the code path under test instead of silently passing.
//
// Every mutating method refuses a cancelled context, the way a real store does.
// Without that a rollback running on the caller's already-cancelled context
// would still appear to succeed here, and the test could not tell it apart from
// one that ran on the uncancelled rollbackCtx.

// fakeDocumentStore is a content-addressed in-memory storeconn.DocumentStore:
// it holds files by name and content hash and knows nothing about versions,
// like the S3 store it models.
type fakeDocumentStore struct {
	storeconn.DocumentStore

	stored map[docdb.FileInfo]struct{} // (Name, Hash) of every stored file

	// prevFiles is what DocumentHashFileProvider hands a CreateVersionFunc as
	// the previous version's files. stored keeps no content, so a test that
	// adds a version has to provide the readable files here.
	prevFiles []fs.FileReader

	writtenVersions   []docdb.VersionTime // versions passed to CreateDocumentVersion
	writtenFiles      []string            // names of every file actually uploaded
	filesExistCalls   int                 // calls to DocumentHashFilesExist
	filesExistChecked int                 // files asked about in total

	// createErr, when set, makes every CreateDocumentVersion fail, modelling a
	// blob write that never succeeds.
	createErr error
	// failWriteOf, when set, makes CreateDocumentVersion fail for that version
	// only, modelling a blob write that dies mid-restore.
	failWriteOf *docdb.VersionTime
	// panicOn, when set, makes CreateDocumentVersion panic for that version,
	// modelling a store client that panics rather than returning an error.
	panicOn *docdb.VersionTime
	// cancelWrite, when set, is called at the start of CreateDocumentVersion so
	// a test can cancel the caller's context in the middle of a write, which is
	// where a half-written document comes from.
	cancelWrite context.CancelFunc

	deleteDocumentCalls int
	deletedHashes       []string
}

// newFakeDocumentStore returns a store already holding the passed files, which
// is what an interrupted copy leaves behind.
func newFakeDocumentStore(files ...docdb.FileInfo) *fakeDocumentStore {
	store := &fakeDocumentStore{stored: make(map[docdb.FileInfo]struct{})}
	for _, file := range files {
		store.stored[file] = struct{}{}
	}
	return store
}

func (d *fakeDocumentStore) DocumentExists(context.Context, uu.ID) (bool, error) {
	return len(d.stored) > 0, nil
}

func (d *fakeDocumentStore) DocumentHashFilesExist(_ context.Context, _ uu.ID, files []docdb.FileInfo) (map[docdb.FileInfo]bool, error) {
	d.filesExistCalls++
	d.filesExistChecked += len(files)
	exist := make(map[docdb.FileInfo]bool, len(files))
	for _, file := range files {
		_, exist[file] = d.stored[file]
	}
	return exist, nil
}

func (d *fakeDocumentStore) DocumentHashFileProvider(context.Context, uu.ID, []string) (docdb.FileProvider, error) {
	return docdb.NewFileProvider(d.prevFiles...), nil
}

func (d *fakeDocumentStore) DeleteDocument(ctx context.Context, docID uu.ID) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	d.deleteDocumentCalls++
	if len(d.stored) == 0 {
		// Same as s3store: deleting nothing means the document is not there.
		return docdb.NewErrDocumentNotFound(docID)
	}
	clear(d.stored)
	return nil
}

func (d *fakeDocumentStore) DeleteDocumentHashes(ctx context.Context, _ uu.ID, hashes []string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	d.deletedHashes = append(d.deletedHashes, hashes...)
	for file := range d.stored {
		if slices.Contains(hashes, file.Hash) {
			delete(d.stored, file)
		}
	}
	return nil
}

func (d *fakeDocumentStore) CreateDocumentVersion(ctx context.Context, _ uu.ID, version docdb.VersionTime, files []fs.FileReader) ([]*docdb.FileInfo, error) {
	if d.panicOn != nil && d.panicOn.Equal(version) {
		panic("document store blew up")
	}
	if d.cancelWrite != nil {
		d.cancelWrite()
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if d.createErr != nil {
		return nil, d.createErr
	}
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
		d.writtenFiles = append(d.writtenFiles, info.Name)
		fileInfos[i] = &docdb.FileInfo{Name: info.Name, Size: int64(len(data)), Hash: info.Hash}
	}
	return fileInfos, nil
}

// has reports whether every file of the version is stored.
func (d *fakeDocumentStore) has(doc *docdb.HashedDocument, version docdb.VersionTime) bool {
	for filename, hash := range doc.Versions[version].FileHashes {
		if _, ok := d.stored[docdb.FileInfo{Name: filename, Hash: hash}]; !ok {
			return false
		}
	}
	return true
}

// fakeMetadataStore is an in-memory storeconn.MetadataStore keyed by version.
// A store already holding every version of a document is the state a migration
// into a shared MetadataStore starts from: the version rows were mirrored long
// before any file content was copied.
type fakeMetadataStore struct {
	storeconn.MetadataStore

	companyID uu.ID
	// stored is the version metadata the store already holds, keyed by version.
	stored map[docdb.VersionTime]*docdb.VersionInfo

	// versionsExist models pgstore.ContextWithMetadataStoreVersionsExist: the
	// store inserts nothing and verifies instead, so a create for an
	// already-stored version succeeds. When false the store really inserts and
	// rejects a duplicate the way Postgres does.
	versionsExist bool

	// createVersionErr, when set, is returned by CreateDocumentVersion to
	// simulate a metadata insert failure after the blobs were written.
	createVersionErr error
	// panicOnCreateVersion makes CreateDocumentVersion panic instead of
	// inserting, modelling a store client that panics rather than returning an
	// error.
	panicOnCreateVersion bool
	// safeHashesToDelete models the sibling-safe set the real
	// DeleteDocumentVersion SQL returns: only hashes referenced solely by the
	// version being deleted (hashes still shared with a sibling are excluded).
	safeHashesToDelete []string

	insertedVersions    []docdb.VersionTime
	deletedVersions     []docdb.VersionTime
	deleteDocumentCalls int
}

// newFakeMetadataStore returns a store already holding the passed versions.
func newFakeMetadataStore(versions ...*docdb.VersionInfo) *fakeMetadataStore {
	store := &fakeMetadataStore{stored: make(map[docdb.VersionTime]*docdb.VersionInfo, len(versions))}
	for _, info := range versions {
		store.companyID = info.CompanyID
		store.stored[info.Version] = info
	}
	return store
}

// newRestoreMetadataStore returns a store already holding the passed versions
// of doc, exactly as the backup describes them.
func newRestoreMetadataStore(t *testing.T, doc *docdb.HashedDocument, versions ...docdb.VersionTime) *fakeMetadataStore {
	t.Helper()
	store := newFakeMetadataStore()
	store.companyID = doc.CompanyID
	for _, v := range versions {
		info, err := doc.VersionInfo(v)
		require.NoError(t, err)
		store.stored[v] = info
	}
	return store
}

func (m *fakeMetadataStore) DocumentCompanyID(context.Context, uu.ID) (uu.ID, error) {
	return m.companyID, nil
}

func (m *fakeMetadataStore) DocumentVersions(_ context.Context, docID uu.ID) ([]docdb.VersionTime, error) {
	if len(m.stored) == 0 {
		// Same as pgstore: a document without versions is not found.
		return nil, docdb.NewErrDocumentNotFound(docID)
	}
	return slices.SortedFunc(maps.Keys(m.stored), docdb.VersionTime.Compare), nil
}

func (m *fakeMetadataStore) DocumentVersionInfo(_ context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error) {
	info, ok := m.stored[version]
	if !ok {
		return nil, docdb.NewErrDocumentVersionNotFound(docID, version)
	}
	return info, nil
}

func (m *fakeMetadataStore) LatestDocumentVersionInfo(_ context.Context, docID uu.ID) (*docdb.VersionInfo, error) {
	if len(m.stored) == 0 {
		return nil, docdb.NewErrDocumentNotFound(docID)
	}
	latest := slices.MaxFunc(slices.Collect(maps.Keys(m.stored)), docdb.VersionTime.Compare)
	return m.stored[latest], nil
}

func (m *fakeMetadataStore) DeleteDocument(ctx context.Context, docID uu.ID) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	m.deleteDocumentCalls++
	if len(m.stored) == 0 {
		// Same as pgstore: deleting no version means the document is not there.
		return docdb.NewErrDocumentNotFound(docID)
	}
	clear(m.stored)
	return nil
}

func (m *fakeMetadataStore) DeleteDocumentVersion(ctx context.Context, _ uu.ID, version docdb.VersionTime) ([]docdb.VersionTime, []string, error) {
	if err := ctx.Err(); err != nil {
		return nil, nil, err
	}
	m.deletedVersions = append(m.deletedVersions, version)
	delete(m.stored, version)
	return slices.SortedFunc(maps.Keys(m.stored), docdb.VersionTime.Compare), m.safeHashesToDelete, nil
}

func (m *fakeMetadataStore) CreateDocumentVersion(_ context.Context, in storeconn.CreateDocumentVersionInput) (*docdb.VersionInfo, error) {
	if m.panicOnCreateVersion {
		panic("metadata store blew up")
	}
	if m.createVersionErr != nil {
		return nil, m.createVersionErr
	}
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
		DocID:       in.DocID,
		CompanyID:   in.CompanyID,
		Version:     in.NewVersion,
		PrevVersion: in.PreviousVersion,
		Files:       in.Files,
	}
	m.insertedVersions = append(m.insertedVersions, in.NewVersion)
	return m.stored[in.NewVersion], nil
}
