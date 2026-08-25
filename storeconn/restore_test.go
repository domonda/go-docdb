package storeconn_test

import (
	"errors"
	"os"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/storeconn"
)

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
			docs := newFakeDocumentStore(docdb.FileInfo{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]})
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

	docs := newFakeDocumentStore(
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

	docs := newFakeDocumentStore(docdb.FileInfo{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]})
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
			docs := newFakeDocumentStore() // nothing copied yet
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
	docs := newFakeDocumentStore()
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

	docs := newFakeDocumentStore(docdb.FileInfo{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]})
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

// TestConn_RestoreDocument_RollsBackOnPanic verifies that a panic from a store
// is rolled back like an error. The rollback runs only when the call ends with
// an error, so a panic travelling past it would leave behind exactly the
// committed-metadata-without-file-content state the restore has to repair —
// and the caller would see a panic instead of an error.
func TestConn_RestoreDocument_RollsBackOnPanic(t *testing.T) {
	companyID := uu.IDv4()
	docID := uu.IDv4()
	doc, _, v2 := newRestoreTestDoc(companyID, docID)

	docs := newFakeDocumentStore()
	docs.panicOn = &v2
	meta := newRestoreMetadataStore(t, doc) // knows nothing yet
	conn := storeconn.New(docs, meta)

	err := conn.RestoreDocument(t.Context(), doc, false)
	require.ErrorContains(t, err, "document store blew up")

	// v1 was created by this call, so the rollback removed it again.
	require.Empty(t, meta.stored, "the version created before the panic must be rolled back")
	require.Equal(t, 1, meta.deleteDocumentCalls+len(meta.deletedVersions))
}

// TestConn_DeleteDocument_DeletesFileContentWithoutMetadata covers a document
// whose metadata is gone but whose file content is not — what a failure or
// cancellation between the two deletes, or between the two writes, leaves
// behind. Reporting the MetadataStore's not-found without touching the
// DocumentStore orphaned that content permanently, because every later delete
// stopped at the same not-found.
func TestConn_DeleteDocument_DeletesFileContentWithoutMetadata(t *testing.T) {
	companyID := uu.IDv4()
	docID := uu.IDv4()
	doc, v1, _ := newRestoreTestDoc(companyID, docID)

	docs := newFakeDocumentStore(docdb.FileInfo{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]})
	meta := newRestoreMetadataStore(t, doc) // no version metadata at all
	conn := storeconn.New(docs, meta)

	require.NoError(t, conn.DeleteDocument(t.Context(), docID))
	require.Empty(t, docs.stored, "file content without metadata must be deleted too")

	// A document neither store holds is still reported as not found.
	err := conn.DeleteDocument(t.Context(), uu.IDv4())
	require.ErrorIs(t, err, os.ErrNotExist)
}

// TestConn_RestoreDocument_RecreateRepairsFileContentWithoutMetadata covers
// re-creating such a document: the up-front delete must not fail on the missing
// metadata, or the document could never be restored again.
func TestConn_RestoreDocument_RecreateRepairsFileContentWithoutMetadata(t *testing.T) {
	companyID := uu.IDv4()
	docID := uu.IDv4()
	doc, v1, v2 := newRestoreTestDoc(companyID, docID)

	docs := newFakeDocumentStore(docdb.FileInfo{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]})
	meta := newRestoreMetadataStore(t, doc) // no version metadata at all
	conn := storeconn.New(docs, meta)

	require.NoError(t, conn.RestoreDocument(t.Context(), doc, true))
	require.Equal(t, []docdb.VersionTime{v1, v2}, meta.insertedVersions)
	require.True(t, docs.has(doc, v1))
	require.True(t, docs.has(doc, v2))
}

// TestConn_RestoreDocument_RecreateRepairsMetadataWithoutFileContent covers the
// mirror of the case above: the metadata is there and the file content is not.
// That is what a migration which mirrored the version rows long before copying
// any blob leaves behind, and what a write cancelled between the two steps
// leaves behind.
//
// The up-front delete used to be gated on DocumentExists, which reports only
// what the DocumentStore holds, so for such a document it was skipped. The loop
// then took the genesis path for a version the MetadataStore already had, which
// the one-genesis-per-document index refuses with ErrDocumentAlreadyExists —
// and CreateDocument's rollback deliberately keeps the blobs it wrote for that
// error, because under concurrency they belong to the winner. So recreate
// failed on exactly the state it is asked for, and left new orphaned content.
func TestConn_RestoreDocument_RecreateRepairsMetadataWithoutFileContent(t *testing.T) {
	companyID := uu.IDv4()
	docID := uu.IDv4()
	doc, v1, v2 := newRestoreTestDoc(companyID, docID)

	docs := newFakeDocumentStore()                  // no file content at all
	meta := newRestoreMetadataStore(t, doc, v1, v2) // every version already mirrored
	conn := storeconn.New(docs, meta)

	require.NoError(t, conn.RestoreDocument(t.Context(), doc, true))

	require.Positive(t, meta.deleteDocumentCalls, "recreate must delete the metadata-only document first")
	require.Equal(t, []docdb.VersionTime{v1, v2}, meta.insertedVersions)
	require.True(t, docs.has(doc, v1))
	require.True(t, docs.has(doc, v2))
}

// TestConn_RestoreDocument_MergeWritesOnlyMissingFiles pins that a version
// whose content is only partly missing costs only the missing part.
//
// The presence of every candidate file is already established per file, so
// reducing that to "this version is not fully stored" and then re-uploading all
// of it wastes a full upload of every file that was already there. Files are
// content-addressed by name and hash, so a file carried forward unchanged is
// one object no matter how many versions reference it, and writing it once is
// enough for all of them.
func TestConn_RestoreDocument_MergeWritesOnlyMissingFiles(t *testing.T) {
	doc, v1, v2 := newRestoreTestDoc(uu.IDv4(), uu.IDv4())

	// The interrupted run got as far as a.txt, which v1 and v2 share, so only
	// v2's b.txt is missing.
	docs := newFakeDocumentStore(docdb.FileInfo{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]})
	meta := newRestoreMetadataStore(t, doc, v1, v2)
	meta.versionsExist = true
	conn := storeconn.New(docs, meta)

	require.NoError(t, conn.RestoreDocument(t.Context(), doc, false))

	require.True(t, docs.has(doc, v1))
	require.True(t, docs.has(doc, v2))
	require.Equal(t, []docdb.VersionTime{v2}, docs.writtenVersions, "v1 was complete")
	require.Equal(t, []string{"b.txt"}, docs.writtenFiles,
		"a.txt was already stored, so only the missing b.txt may be uploaded")
}

// TestConn_RestoreDocument_WritesCarriedForwardFileOnce covers a document
// neither store knows: every file is written, but a file that later versions
// carry forward unchanged is the same object and must not be uploaded again
// for each of them.
func TestConn_RestoreDocument_WritesCarriedForwardFileOnce(t *testing.T) {
	doc, v1, v2 := newRestoreTestDoc(uu.IDv4(), uu.IDv4())

	docs := newFakeDocumentStore() // empty
	meta := newRestoreMetadataStore(t, doc)
	conn := storeconn.New(docs, meta)

	require.NoError(t, conn.RestoreDocument(t.Context(), doc, false))

	require.True(t, docs.has(doc, v1))
	require.True(t, docs.has(doc, v2))
	// a.txt belongs to both versions but is one object.
	require.ElementsMatch(t, []string{"a.txt", "b.txt"}, docs.writtenFiles)
	require.Len(t, docs.writtenFiles, 2, "a.txt is carried forward unchanged, so it is written once")
}

// TestConn_RestoreDocument_RollsBackFileContentOfPreExistingVersions covers the
// rollback of a restore into a MetadataStore that already holds every version.
//
// That is the migration case: the version rows were mirrored long before any
// file content was copied, so no version the restore writes files for is one it
// added to the MetadataStore, and none of them may be deleted from there on
// failure. The file content is a different matter — this call uploaded it, and
// leaving it behind when the restore fails orphans objects that nothing
// references and that no later run will clean up, because the next attempt
// finds them present and skips them.
func TestConn_RestoreDocument_RollsBackFileContentOfPreExistingVersions(t *testing.T) {
	doc, v1, v2 := newRestoreTestDoc(uu.IDv4(), uu.IDv4())

	docs := newFakeDocumentStore() // no file content at all
	docs.failWriteOf = &v2         // the second version's upload dies
	meta := newRestoreMetadataStore(t, doc, v1, v2)
	meta.versionsExist = true
	conn := storeconn.New(docs, meta)

	require.Error(t, conn.RestoreDocument(t.Context(), doc, false))

	require.Zero(t, meta.deleteDocumentCalls, "the pre-existing metadata is not this call's to delete")
	require.False(t, docs.has(doc, v1), "v1's content was uploaded by this call and must be rolled back")
	// Both files: v1's because it was uploaded, and v2's because the upload
	// that failed may still have stored some of its objects before it did.
	// Deleted by name and hash together, never by hash alone.
	require.ElementsMatch(t,
		[]docdb.FileInfo{
			{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]},
			{Name: "b.txt", Hash: doc.Versions[v2].FileHashes["b.txt"]},
		},
		docs.deletedFiles,
	)
	require.Empty(t, docs.deletedHashes, "the rollback must not delete by hash alone")
}

// TestConn_RestoreDocument_RollbackKeepsPreExistingFileContent is the
// counterpart: the rollback deletes the objects this call uploaded, never one
// that was already there. An interrupted earlier run left a.txt behind, so the
// restore only writes b.txt and only b.txt may be removed again — deleting
// a.txt would destroy content of a version the restore never touched.
func TestConn_RestoreDocument_RollbackKeepsPreExistingFileContent(t *testing.T) {
	doc, v1, v2 := newRestoreTestDoc(uu.IDv4(), uu.IDv4())

	hashA := doc.Versions[v1].FileHashes["a.txt"]
	docs := newFakeDocumentStore(docdb.FileInfo{Name: "a.txt", Hash: hashA})
	docs.failWriteOf = &v2
	meta := newRestoreMetadataStore(t, doc, v1, v2)
	meta.versionsExist = true
	conn := storeconn.New(docs, meta)

	require.Error(t, conn.RestoreDocument(t.Context(), doc, false))

	require.NotContains(t, docs.deletedHashes, hashA, "a.txt was already stored before this call")
	require.True(t, docs.has(doc, v1), "v1 was complete before the call and must stay complete")
}

// newSharedContentDoc returns a three-version backup in which two filenames
// hold byte-identical content, so they share a content hash and therefore the
// hash a rollback would delete by. v1 holds a.txt, v2 adds b.txt with the same
// content as a.txt, v3 adds c.txt.
//
// A carried-forward file plus a rename produces exactly this shape, so it is
// not an exotic document.
func newSharedContentDoc(companyID, docID uu.ID) (doc *docdb.HashedDocument, v1, v2, v3 docdb.VersionTime) {
	v1 = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
	v2 = docdb.MustVersionTimeFromString("2024-01-02_00-00-00.000")
	v3 = docdb.MustVersionTimeFromString("2024-01-03_00-00-00.000")

	shared := []byte("shared content")
	other := []byte("content of c")
	sharedHash := docdb.ContentHash(shared)
	otherHash := docdb.ContentHash(other)

	doc = &docdb.HashedDocument{
		ID:          docID,
		CompanyID:   companyID,
		HashedFiles: map[string][]byte{sharedHash: shared, otherHash: other},
		Versions: map[docdb.VersionTime]*docdb.HashedVersion{
			v1: {CommitUserID: uu.IDv4(), CommitReason: "initial", FileHashes: map[string]string{
				"a.txt": sharedHash,
			}},
			v2: {CommitUserID: uu.IDv4(), CommitReason: "add b", FileHashes: map[string]string{
				"a.txt": sharedHash,
				"b.txt": sharedHash,
			}},
			v3: {CommitUserID: uu.IDv4(), CommitReason: "add c", FileHashes: map[string]string{
				"a.txt": sharedHash,
				"b.txt": sharedHash,
				"c.txt": otherHash,
			}},
		},
	}
	return doc, v1, v2, v3
}

// TestConn_RestoreDocument_RollbackKeepsSameContentUnderAnotherName verifies
// that the rollback deletes the objects this call wrote and not every object
// sharing their content hash.
//
// A hash does not identify one object: a DocumentStore keys a file by name AND
// hash, so a document holding the same bytes under two names holds two objects.
// Rolling back by hash alone deleted both — including the one that was there
// before the restore started, silently corrupting a version the restore was
// never touching. That is the failure path of a migration, which is the one
// path that only runs when something already went wrong.
func TestConn_RestoreDocument_RollbackKeepsSameContentUnderAnotherName(t *testing.T) {
	doc, v1, _, v3 := newSharedContentDoc(uu.IDv4(), uu.IDv4())
	sharedHash := doc.Versions[v1].FileHashes["a.txt"]
	preExisting := docdb.FileInfo{Name: "a.txt", Hash: sharedHash}

	// a.txt is already stored; b.txt holds the same content under another name
	// and is not, so the restore writes it and records its hash.
	docs := newFakeDocumentStore(preExisting)
	docs.failWriteOf = &v3 // the last version's upload dies
	meta := newRestoreMetadataStore(t, doc, v1)
	conn := storeconn.New(docs, meta)

	require.Error(t, conn.RestoreDocument(t.Context(), doc, false))

	require.Contains(t, docs.stored, preExisting,
		"the object that was there before the restore must survive its rollback")
	require.NotContains(t, docs.deletedFiles, preExisting,
		"the rollback must not ask to delete a file it did not write")
	require.Contains(t, docs.deletedFiles, docdb.FileInfo{Name: "b.txt", Hash: sharedHash},
		"the file this call did write must be rolled back")
}

// TestConn_RestoreDocument_RollbackKeepsContentItDidNotWrite verifies that
// rolling back a version this call created does not delete file content that
// was already stored for it.
//
// Such a version exists whenever the DocumentStore holds a version's files but
// the MetadataStore does not know the version: nothing is uploaded for it, only
// its metadata row is created. Rolling that row back through the composite
// DeleteDocumentVersion also deleted the content hashes the row alone
// referenced — content this call never wrote, and which the restore found in
// place. The rollback therefore removes metadata through the MetadataStore and
// deletes only what it uploaded.
func TestConn_RestoreDocument_RollbackKeepsContentItDidNotWrite(t *testing.T) {
	doc, v1, v2 := newRestoreTestDoc(uu.IDv4(), uu.IDv4())
	a := docdb.FileInfo{Name: "a.txt", Hash: doc.Versions[v1].FileHashes["a.txt"]}
	b := docdb.FileInfo{Name: "b.txt", Hash: doc.Versions[v2].FileHashes["b.txt"]}

	// Every file is already stored, so the restore uploads nothing and only
	// creates the metadata the store is missing.
	docs := newFakeDocumentStore(a, b)
	meta := newRestoreMetadataStore(t, doc) // knows no version of the document
	meta.failCreateOf = &v2                 // v1's metadata lands, v2's does not
	// What the real MetadataStore reports as safe to delete with v1 once v2 is
	// gone. Following it would delete content this call never wrote.
	meta.safeHashesToDelete = []string{a.Hash}
	conn := storeconn.New(docs, meta)

	require.Error(t, conn.RestoreDocument(t.Context(), doc, false))

	require.Equal(t, []docdb.VersionTime{v1}, meta.deletedVersions,
		"the metadata row this call created must be rolled back")
	require.Empty(t, meta.stored, "no version metadata may survive the rollback")
	require.Contains(t, docs.stored, a, "content the restore found in place must survive")
	require.Contains(t, docs.stored, b)
	require.Empty(t, docs.deletedFiles, "the rollback wrote nothing, so it may delete nothing")
}

// TestConn_RestoreDocument_RollbackKeepsBlobsWhenMetadataRollbackFails verifies
// that file content is left in place when the metadata rollback did not
// succeed.
//
// A version whose metadata delete failed — the MetadataStore went away
// mid-cleanup — is still committed and still names its files. Deleting those
// files anyway leaves a version pointing at content that is gone, which no
// reader can tell apart from corruption. Orphaned objects are the lesser
// failure: they cost storage, the presence check of the next restore finds
// them, and a content-addressed write of the same bytes overwrites them.
func TestConn_RestoreDocument_RollbackKeepsBlobsWhenMetadataRollbackFails(t *testing.T) {
	doc, v1, v2 := newRestoreTestDoc(uu.IDv4(), uu.IDv4())

	docs := newFakeDocumentStore() // no file content yet
	docs.failWriteOf = &v2         // v1 is written, then v2's upload dies
	// v1 is already in the MetadataStore, so the document is not this call's to
	// drop whole and the rollback goes through the per-version delete below.
	meta := newRestoreMetadataStore(t, doc, v1)
	meta.deleteVersionErr = errors.New("metadata store unreachable")
	conn := storeconn.New(docs, meta)

	err := conn.RestoreDocument(t.Context(), doc, false)
	require.Error(t, err)
	require.ErrorContains(t, err, "metadata store unreachable",
		"the failed metadata rollback must surface, not be swallowed")

	require.Empty(t, docs.deletedFiles,
		"content must be kept while a version that still names it is committed")
	require.True(t, docs.has(doc, v1), "v1's uploaded content must still be there")
}
