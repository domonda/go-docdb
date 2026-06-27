package pgstore_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/storeconn"
	"github.com/domonda/go-docdb/storeconn/pgstore"
	"github.com/domonda/go-docdb/storeconn/pgstore/pgfixtures"
)

var store = pgstore.NewMetadataStore()

func TestCreateDocumentVersion(t *testing.T) {
	t.Run("Creates the first version with every file recorded as added", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		version := docdb.NewVersionTime()
		docID := uu.IDv7()
		companyID := uu.IDv7()

		memFiles := []fs.MemFile{
			{
				FileName: "doc1.pdf",
				FileData: []byte("a"),
			},
			{
				FileName: "doc2.pdf",
				FileData: []byte("b"),
			},
		}
		addedFiles := []*docdb.FileInfo{
			{Name: memFiles[0].FileName, Size: memFiles[0].Size(), Hash: docdb.ContentHash(memFiles[0].FileData)},
			{Name: memFiles[1].FileName, Size: memFiles[1].Size(), Hash: docdb.ContentHash(memFiles[1].FileData)},
		}

		// when: a nil PreviousVersion creates the first (genesis) version
		versionInfo, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID:      docID,
			CompanyID:  companyID,
			UserID:     uu.IDv7(),
			Reason:     "reason",
			NewVersion: version,
			AddedFiles: addedFiles,
		})

		// then
		require.NoError(t, err)
		require.Equal(t, []string{memFiles[0].FileName, memFiles[1].FileName}, versionInfo.AddedFiles)
		require.Nil(t, versionInfo.ModifiedFiles)
		require.Nil(t, versionInfo.RemovedFiles)
		require.Nil(t, versionInfo.PrevVersion)

		// The deployed system relies on the first version's added_files column
		// being persisted with every file of that version (not left empty) and
		// on prev_version being NULL. Assert the stored row, not just the
		// returned VersionInfo.
		savedVersion, err := db.QueryRowAs[pgstore.DocumentVersion](
			ctx,
			/* sql */ `select * from docdb.document_version where document_id = $1 and version = $2`,
			docID,
			version,
		)
		require.NoError(t, err)
		require.Equal(t, []string{memFiles[0].FileName, memFiles[1].FileName}, savedVersion.AddedFiles)
		require.Nil(t, savedVersion.PrevVersion)

		savedFiles, err := db.QueryRowsAsSlice[pgstore.DocumentVersionFile](
			ctx,
			/* sql */ `
			select dvf.* from docdb.document_version_file dvf
			join docdb.document_version dv
				on dv.document_id = $1
				and dv.company_id = $2
				and dv.version = $3
				and dvf.document_version_id = dv.id
			order by dvf.name
			`,
			versionInfo.DocID,
			versionInfo.CompanyID,
			versionInfo.Version,
		)

		require.NoError(t, err)
		require.Equal(t, 2, len(savedFiles))

		require.Equal(t, memFiles[0].FileName, savedFiles[0].Name)
		require.Equal(
			t,
			docdb.ContentHash(memFiles[0].FileData),
			savedFiles[0].Hash,
		)

		require.Equal(t, memFiles[1].FileName, savedFiles[1].Name)
		require.Equal(
			t,
			docdb.ContentHash(memFiles[1].FileData),
			savedFiles[1].Hash,
		)
	})
}

func TestCreateDocumentVersionVersionsExistMode(t *testing.T) {
	fileInfo := func(name, content string) *docdb.FileInfo {
		return &docdb.FileInfo{Name: name, Size: int64(len(content)), Hash: docdb.ContentHash([]byte(content))}
	}

	t.Run("Verifies an existing matching version without inserting new rows", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		version := docdb.NewVersionTime()
		addedFiles := []*docdb.FileInfo{fileInfo("a.pdf", "a"), fileInfo("b.pdf", "b")}

		created, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: version, AddedFiles: addedFiles})
		require.NoError(t, err)

		// when: re-running under versions-exist mode must not insert
		// anything, just verify and return the same VersionInfo.
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		verified, err := store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: version, AddedFiles: addedFiles})

		// then
		require.NoError(t, err)
		require.Equal(t, created, verified)

		// Exactly one version row and two file rows: no duplicate insert.
		versionCount, err := db.QueryRowAs[int](ctx,
			/* sql */ `select count(*) from docdb.document_version where document_id = $1 and version = $2`,
			docID,
			version,
		)
		require.NoError(t, err)
		require.Equal(t, 1, versionCount)

		fileCount, err := db.QueryRowAs[int](ctx,
			/* sql */ `
			select count(*) from docdb.document_version_file dvf
			join docdb.document_version dv on dvf.document_version_id = dv.id
			where dv.document_id = $1 and dv.version = $2
			`,
			docID,
			version,
		)
		require.NoError(t, err)
		require.Equal(t, 2, fileCount)
	})

	t.Run("Verifies a version that has a previous version", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		v1 := docdb.NewVersionTime()
		v2 := docdb.VersionTimeFrom(time.Now().Add(time.Second))

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v1", NewVersion: v1,
			AddedFiles: []*docdb.FileInfo{fileInfo("a.pdf", "a")},
		})
		require.NoError(t, err)

		added := []*docdb.FileInfo{fileInfo("b.pdf", "b")}
		created, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v2", NewVersion: v2, PreviousVersion: &v1, AddedFiles: added})
		require.NoError(t, err)

		// when
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		verified, err := store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v2", NewVersion: v2, PreviousVersion: &v1, AddedFiles: added})

		// then
		require.NoError(t, err)
		require.Equal(t, created, verified)
		// The full file set carries a.pdf forward from v1 plus the new b.pdf.
		require.Equal(t, 2, len(verified.Files))
	})

	t.Run("Ignores the order of added files when comparing", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		version := docdb.NewVersionTime()
		fileA := fileInfo("a.pdf", "a")
		fileB := fileInfo("b.pdf", "b")

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: version,
			AddedFiles: []*docdb.FileInfo{fileA, fileB},
		})
		require.NoError(t, err)

		// when: same file set in reversed order. Callers derive the file lists
		// from map iteration, so order is not significant and must still match.
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		_, err = store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: version,
			AddedFiles: []*docdb.FileInfo{fileB, fileA},
		})

		// then
		require.NoError(t, err)
	})

	t.Run("Returns error when a scalar field differs", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		version := docdb.NewVersionTime()
		addedFiles := []*docdb.FileInfo{fileInfo("a.pdf", "a")}

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: version, AddedFiles: addedFiles})
		require.NoError(t, err)

		// when: same version but a different commit reason
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		_, err = store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: userID, Reason: "different reason", NewVersion: version, AddedFiles: addedFiles})

		// then
		require.ErrorContains(t, err, "does not match")
	})

	t.Run("Returns error when a file's content hash differs", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		version := docdb.NewVersionTime()

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: version,
			AddedFiles: []*docdb.FileInfo{fileInfo("a.pdf", "a")},
		})
		require.NoError(t, err)

		// when: same filename but different content
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		_, err = store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: version,
			AddedFiles: []*docdb.FileInfo{fileInfo("a.pdf", "different")},
		})

		// then
		require.ErrorContains(t, err, "does not match")
	})

	t.Run("Returns error when the companyID differs", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		userID := uu.IDv7()
		version := docdb.NewVersionTime()
		addedFiles := []*docdb.FileInfo{fileInfo("a.pdf", "a")}

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: uu.IDv7(), UserID: userID, Reason: "reason", NewVersion: version, AddedFiles: addedFiles})
		require.NoError(t, err)

		// when: same version but a different companyID
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		_, err = store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: uu.IDv7(), UserID: userID, Reason: "reason", NewVersion: version, AddedFiles: addedFiles})

		// then
		require.ErrorContains(t, err, "does not match")
	})

	t.Run("Returns error when the commitUserID differs", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		version := docdb.NewVersionTime()
		addedFiles := []*docdb.FileInfo{fileInfo("a.pdf", "a")}

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: uu.IDv7(), Reason: "reason", NewVersion: version, AddedFiles: addedFiles})
		require.NoError(t, err)

		// when: same version but a different commitUserID
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		_, err = store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: uu.IDv7(), Reason: "reason", NewVersion: version, AddedFiles: addedFiles})

		// then
		require.ErrorContains(t, err, "does not match")
	})

	t.Run("Returns error when the previousVersion differs", func(t *testing.T) {
		// given: a genesis version plus a second version that points at it.
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		v1 := docdb.NewVersionTime()
		v2 := docdb.VersionTimeFrom(time.Now().Add(time.Second))

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v1", NewVersion: v1,
			AddedFiles: []*docdb.FileInfo{fileInfo("a.pdf", "a")},
		})
		require.NoError(t, err)

		added := []*docdb.FileInfo{fileInfo("b.pdf", "b")}
		_, err = store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v2", NewVersion: v2, PreviousVersion: &v1, AddedFiles: added})
		require.NoError(t, err)

		// when: verify v2 as a genesis version (nil previousVersion) although it
		// was stored with v1 as its previousVersion.
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		_, err = store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v2", NewVersion: v2, AddedFiles: added})

		// then
		require.ErrorContains(t, err, "does not match")
	})

	t.Run("Returns error when the added files differ", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		version := docdb.NewVersionTime()

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: version,
			AddedFiles: []*docdb.FileInfo{fileInfo("a.pdf", "a"), fileInfo("b.pdf", "b")},
		})
		require.NoError(t, err)

		// when: the same version is verified with a smaller set of added files
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		_, err = store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: version,
			AddedFiles: []*docdb.FileInfo{fileInfo("a.pdf", "a")},
		})

		// then
		require.ErrorContains(t, err, "does not match")
	})

	t.Run("Returns error when the modified files differ", func(t *testing.T) {
		// given: a genesis version, then a second version that modifies a.pdf.
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		v1 := docdb.NewVersionTime()
		v2 := docdb.VersionTimeFrom(time.Now().Add(time.Second))

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v1", NewVersion: v1,
			AddedFiles: []*docdb.FileInfo{fileInfo("a.pdf", "a")},
		})
		require.NoError(t, err)

		_, err = store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v2", NewVersion: v2, PreviousVersion: &v1,
			ModifiedFiles: []*docdb.FileInfo{fileInfo("a.pdf", "a2")},
		})
		require.NoError(t, err)

		// when: verify v2 without recording a.pdf as modified
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		_, err = store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v2", NewVersion: v2, PreviousVersion: &v1})

		// then
		require.ErrorContains(t, err, "does not match")
	})

	t.Run("Returns error when the removed files differ", func(t *testing.T) {
		// given: a genesis version with two files, then a second version that
		// removes b.pdf.
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		v1 := docdb.NewVersionTime()
		v2 := docdb.VersionTimeFrom(time.Now().Add(time.Second))

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v1", NewVersion: v1,
			AddedFiles: []*docdb.FileInfo{fileInfo("a.pdf", "a"), fileInfo("b.pdf", "b")},
		})
		require.NoError(t, err)

		_, err = store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v2", NewVersion: v2, PreviousVersion: &v1,
			RemovedFiles: []string{"b.pdf"},
		})
		require.NoError(t, err)

		// when: verify v2 without recording b.pdf as removed
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		_, err = store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v2", NewVersion: v2, PreviousVersion: &v1})

		// then
		require.ErrorContains(t, err, "does not match")
	})

	t.Run("Returns error when the assumed version does not exist", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		assumeCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		_, err := store.CreateDocumentVersion(assumeCtx, storeconn.CreateDocumentVersionInput{
			DocID: uu.IDv7(), CompanyID: uu.IDv7(), UserID: uu.IDv7(), Reason: "reason",
			NewVersion: docdb.NewVersionTime(), AddedFiles: []*docdb.FileInfo{fileInfo("a.pdf", "a")},
		})

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestCreateDocumentVersionMissingPreviousVersion(t *testing.T) {
	t.Parallel()
	ctx := pgfixtures.FixtureCtxWithTestTx(t)
	docID := uu.IDv7()
	companyID := uu.IDv7()
	userID := uu.IDv7()

	// previousVersion points to a version that was never stored. Building the
	// carried-forward file set must fail explicitly rather than silently treat
	// the missing previous version as having zero files (which would persist a
	// new version missing its carried-forward files).
	missingPrev := docdb.NewVersionTime()
	newVersion := docdb.VersionTimeFrom(time.Now().Add(time.Second))

	_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
		DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason",
		NewVersion: newVersion, PreviousVersion: &missingPrev,
		AddedFiles: []*docdb.FileInfo{{Name: "b.pdf", Size: 1, Hash: docdb.ContentHash([]byte("b"))}},
	})

	require.Error(t, err)
	require.ErrorIs(t, err, errs.ErrNotFound)
	require.ErrorContains(t, err, "carry files forward")
}

func TestCreateDocumentVersionWithExplicitFiles(t *testing.T) {
	t.Parallel()
	ctx := pgfixtures.FixtureCtxWithTestTx(t)
	docID := uu.IDv7()
	companyID := uu.IDv7()
	userID := uu.IDv7()

	// Passing the resolved Files set must make CreateDocumentVersion store it
	// directly and skip the predecessor lookup: a previousVersion that was never
	// stored (which would otherwise fail with a carry-files-forward not-found
	// error, see TestCreateDocumentVersionMissingPreviousVersion) is not queried.
	missingPrev := docdb.NewVersionTime()
	newVersion := docdb.VersionTimeFrom(time.Now().Add(time.Second))
	fileA := docdb.FileInfo{Name: "a.pdf", Size: 1, Hash: docdb.ContentHash([]byte("a"))}
	fileB := docdb.FileInfo{Name: "b.pdf", Size: 1, Hash: docdb.ContentHash([]byte("b"))}
	wantFiles := map[string]docdb.FileInfo{fileA.Name: fileA, fileB.Name: fileB}

	info, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
		DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason",
		NewVersion: newVersion, PreviousVersion: &missingPrev,
		// Only b.pdf is a delta, but Files is the full set (a.pdf carried forward).
		AddedFiles: []*docdb.FileInfo{&fileB},
		Files:      wantFiles,
	})
	require.NoError(t, err)
	require.Equal(t, wantFiles, info.Files)

	// The stored document_version_file rows must match the provided Files set,
	// not just the AddedFiles delta.
	stored, err := store.DocumentVersionInfo(ctx, docID, newVersion)
	require.NoError(t, err)
	require.Equal(t, wantFiles, stored.Files)
}

func TestCreateDocumentVersionDuplicate(t *testing.T) {
	addedFiles := []*docdb.FileInfo{{Name: "a.pdf", Size: 1, Hash: docdb.ContentHash([]byte("a"))}}

	t.Run("Genesis duplicate maps the unique violation to ErrDocumentAlreadyExists", func(t *testing.T) {
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		version := docdb.NewVersionTime()

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: version, AddedFiles: addedFiles,
		})
		require.NoError(t, err)

		// Re-inserting the same genesis (document_id, version) hits the unique
		// constraint, which must surface as ErrDocumentAlreadyExists.
		_, err = store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: version, AddedFiles: addedFiles,
		})
		require.ErrorIs(t, err, docdb.NewErrDocumentAlreadyExists(docID))
	})

	t.Run("Second genesis with a different version maps to ErrDocumentAlreadyExists", func(t *testing.T) {
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		v1 := docdb.NewVersionTime()
		v2 := docdb.VersionTimeFrom(time.Now().Add(time.Second))

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "reason", NewVersion: v1, AddedFiles: addedFiles,
		})
		require.NoError(t, err)

		// A second genesis (prev_version NULL) with a DIFFERENT version must be
		// rejected by the single-genesis partial unique index, not silently
		// inserted as a duplicate genesis.
		_, err = store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "second genesis", NewVersion: v2, AddedFiles: addedFiles,
		})
		require.ErrorIs(t, err, docdb.NewErrDocumentAlreadyExists(docID))
	})

	t.Run("Appended-version duplicate maps the unique violation to ErrVersionAlreadyExists", func(t *testing.T) {
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()
		companyID := uu.IDv7()
		userID := uu.IDv7()
		v1 := docdb.NewVersionTime()
		v2 := docdb.VersionTimeFrom(time.Now().Add(time.Second))

		_, err := store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v1", NewVersion: v1, AddedFiles: addedFiles,
		})
		require.NoError(t, err)

		added := []*docdb.FileInfo{{Name: "b.pdf", Size: 1, Hash: docdb.ContentHash([]byte("b"))}}
		_, err = store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v2", NewVersion: v2, PreviousVersion: &v1, AddedFiles: added,
		})
		require.NoError(t, err)

		// Re-inserting an appended version maps the same constraint to the
		// version-scoped error instead of the document-scoped one.
		_, err = store.CreateDocumentVersion(ctx, storeconn.CreateDocumentVersionInput{
			DocID: docID, CompanyID: companyID, UserID: userID, Reason: "v2", NewVersion: v2, PreviousVersion: &v1, AddedFiles: added,
		})
		require.ErrorIs(t, err, docdb.NewErrVersionAlreadyExists(docID, v2))
	})
}

func TestDocumentCompanyID(t *testing.T) {

	// In theory all versions should have the same company_id, but if not, return the company_id from the most recent version
	t.Run("Returns company ID from the latest version", func(t *testing.T) {
		// given
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		docVersion1 := populator.DocumentVersion()
		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		clientCompanyId, err := store.DocumentCompanyID(
			ctx,
			docVersion1.DocumentID,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion2.CompanyID, clientCompanyId)
	})

	t.Run("Returns error if document not found", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		_, err := store.DocumentCompanyID(
			ctx,
			uu.IDv7(),
		)

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestSetDocumentCompanyID(t *testing.T) {
	t.Run("Sets the company ID for all versions", func(t *testing.T) {
		// given
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		docVersion1 := populator.DocumentVersion()
		populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		newCompanyID := uu.IDv7()
		err := store.SetDocumentCompanyID(ctx, docVersion1.DocumentID, newCompanyID)

		// then
		require.NoError(t, err)

		savedDocumentVersions, err := db.QueryRowsAsSlice[pgstore.DocumentVersion](
			ctx,
			/* sql */ `select * from docdb.document_version where document_id = $1`,
			docVersion1.DocumentID,
		)
		require.NoError(t, err)
		require.Equal(t, 2, len(savedDocumentVersions))
		for i := range 2 {
			require.Equal(t, newCompanyID, savedDocumentVersions[i].CompanyID)
		}
	})

	t.Run("Returns error if document version does not exist", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		err := store.SetDocumentCompanyID(ctx, uu.IDv7(), uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestDocumentVersions(t *testing.T) {
	t.Run("Returns all versions belonging to a document", func(t *testing.T) {
		// given
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		docVersion1 := populator.DocumentVersion()
		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		// not wanted, different doc ID
		populator.DocumentVersion()

		// when
		versions, err := store.DocumentVersions(ctx, docVersion1.DocumentID)

		// then
		require.NoError(t, err)
		require.Equal(t, 2, len(versions))
		// Versions must be returned in ascending order (oldest first),
		// as documented by the MetadataStore.DocumentVersions contract.
		require.Equal(t, docVersion1.Version, versions[0])
		require.Equal(t, docVersion2.Version, versions[1])
	})

	t.Run("Returns error if no versions", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		_, err := store.DocumentVersions(ctx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestEnumCompanyDocumentIDs(t *testing.T) {
	t.Run("Iterates over all company related documents", func(t *testing.T) {
		// given
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		doc1Version1 := populator.DocumentVersion(map[string]any{"DocumentID": uu.IDFrom("a3c60853-022c-403d-85cc-6ea146ec6a4a")})
		populator.DocumentVersion(map[string]any{
			"DocumentID": doc1Version1.DocumentID,
			"CompanyID":  doc1Version1.CompanyID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		doc2Version1 := populator.DocumentVersion(map[string]any{
			"DocumentID": uu.IDFrom("c7e67e60-9548-43c6-83be-55cb736a5761"),
			"CompanyID":  doc1Version1.CompanyID,
		})

		// not wanted
		populator.DocumentVersion()

		// when
		processedDocumentIDs := []uu.ID{}
		store.EnumCompanyDocumentIDs(
			ctx,
			doc1Version1.CompanyID,
			func(ctx context.Context, i uu.ID) error {
				processedDocumentIDs = append(processedDocumentIDs, i)
				return nil
			},
		)

		// then
		require.Equal(t, 2, len(processedDocumentIDs))
		require.Equal(t, doc1Version1.DocumentID, processedDocumentIDs[0])
		require.Equal(t, doc2Version1.DocumentID, processedDocumentIDs[1])
	})

	t.Run("Returns no error if no versions", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		err := store.EnumCompanyDocumentIDs(
			ctx,
			uu.IDv7(),
			func(ctx context.Context, i uu.ID) error { return nil },
		)

		// then
		require.NoError(t, err)
	})

	t.Run("Returns error from callback", func(t *testing.T) {
		// given
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docVersion := populator.DocumentVersion()

		// when
		expectedErr := errors.New("bug")
		err := store.EnumCompanyDocumentIDs(
			ctx,
			docVersion.CompanyID,
			func(ctx context.Context, i uu.ID) error {
				return expectedErr
			},
		)

		// then
		require.ErrorIs(t, err, expectedErr)
	})
}

func TestLatestDocumentVersion(t *testing.T) {
	t.Run("Returns latest document version", func(t *testing.T) {
		// given
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		docVersion1 := populator.DocumentVersion()
		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		// not wanted, different doc ID
		populator.DocumentVersion()

		// when
		version, err := store.LatestDocumentVersion(ctx, docVersion1.DocumentID)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion2.Version, version)
	})

	t.Run("Returns error if no version found", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		_, err := store.LatestDocumentVersion(ctx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestDocumentVersionInfo(t *testing.T) {
	t.Run("Returns document version info", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		docVersionFile1 := populator.DocumentVersionFile()

		docVersionFile2 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": docVersionFile1.DocumentVersion,
		})

		// not wanted
		populator.DocumentVersionFile()

		// when
		versionInfo, err := store.DocumentVersionInfo(
			ctx,
			docVersionFile1.DocumentVersion.DocumentID,
			docVersionFile1.DocumentVersion.Version,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersionFile1.DocumentVersion.DocumentID, versionInfo.DocID)
		require.Equal(t, docVersionFile1.DocumentVersion.CompanyID, versionInfo.CompanyID)
		require.Equal(t, docVersionFile1.DocumentVersion.Version, versionInfo.Version)
		require.Equal(t, docVersionFile1.DocumentVersion.PrevVersion, versionInfo.PrevVersion)
		require.Equal(t, docVersionFile1.DocumentVersion.AddedFiles, versionInfo.AddedFiles)
		require.Equal(t, docVersionFile1.DocumentVersion.ModifiedFiles, versionInfo.ModifiedFiles)
		require.Equal(t, docVersionFile1.DocumentVersion.RemovedFiles, versionInfo.RemovedFiles)

		require.Equal(t, 2, len(versionInfo.Files))

		file := versionInfo.Files[docVersionFile1.Name]
		require.Equal(t, docVersionFile1.Name, file.Name)
		require.Equal(t, docVersionFile1.Hash, file.Hash)
		require.Equal(t, docVersionFile1.Size, file.Size)

		file = versionInfo.Files[docVersionFile2.Name]
		require.Equal(t, docVersionFile2.Name, file.Name)
		require.Equal(t, docVersionFile2.Hash, file.Hash)
		require.Equal(t, docVersionFile2.Size, file.Size)
	})

	t.Run("Returns document version info without files", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		docVersion := populator.DocumentVersion()

		// not wanted
		populator.DocumentVersionFile()

		// when
		versionInfo, err := store.DocumentVersionInfo(
			ctx,
			docVersion.DocumentID,
			docVersion.Version,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion.DocumentID, versionInfo.DocID)
		require.Equal(t, docVersion.CompanyID, versionInfo.CompanyID)
		require.Equal(t, docVersion.Version, versionInfo.Version)
		require.Equal(t, docVersion.PrevVersion, versionInfo.PrevVersion)
		require.Equal(t, docVersion.AddedFiles, versionInfo.AddedFiles)
		require.Equal(t, docVersion.ModifiedFiles, versionInfo.ModifiedFiles)
		require.Equal(t, docVersion.RemovedFiles, versionInfo.RemovedFiles)
	})

	t.Run("Returns error if no version info found", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		_, err := store.DocumentVersionInfo(ctx, uu.IDv7(), docdb.VersionTimeFrom(time.Now()))

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestLatestDocumentVersionInfo(t *testing.T) {
	t.Run("Returns latest document version info", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		// older, not wanted
		docVersion1File := populator.DocumentVersionFile()

		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1File.DocumentVersion.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})

		// expected
		docVersion2File1 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": docVersion2,
		})
		docVersion2File2 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": docVersion2,
		})

		// not wanted
		populator.DocumentVersionFile()

		// when
		versionInfo, err := store.LatestDocumentVersionInfo(
			ctx,
			docVersion2.DocumentID,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion2.DocumentID, versionInfo.DocID)
		require.Equal(t, docVersion2.CompanyID, versionInfo.CompanyID)
		require.Equal(t, docVersion2.Version, versionInfo.Version)
		require.Equal(t, docVersion2.PrevVersion, versionInfo.PrevVersion)
		require.Equal(t, docVersion2.AddedFiles, versionInfo.AddedFiles)
		require.Equal(t, docVersion2.ModifiedFiles, versionInfo.ModifiedFiles)
		require.Equal(t, docVersion2.RemovedFiles, versionInfo.RemovedFiles)

		require.Equal(t, 2, len(versionInfo.Files))

		file := versionInfo.Files[docVersion2File1.Name]
		require.Equal(t, docVersion2File1.Name, file.Name)
		require.Equal(t, docVersion2File1.Hash, file.Hash)
		require.Equal(t, docVersion2File1.Size, file.Size)

		file = versionInfo.Files[docVersion2File2.Name]
		require.Equal(t, docVersion2File2.Name, file.Name)
		require.Equal(t, docVersion2File2.Hash, file.Hash)
		require.Equal(t, docVersion2File2.Size, file.Size)
	})

	t.Run("Returns latest document version info without files", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		docVersion := populator.DocumentVersion()

		// not wanted
		populator.DocumentVersionFile()

		// when
		versionInfo, err := store.LatestDocumentVersionInfo(
			ctx,
			docVersion.DocumentID,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion.DocumentID, versionInfo.DocID)
		require.Equal(t, docVersion.CompanyID, versionInfo.CompanyID)
		require.Equal(t, docVersion.Version, versionInfo.Version)
		require.Equal(t, docVersion.PrevVersion, versionInfo.PrevVersion)
		require.Equal(t, docVersion.AddedFiles, versionInfo.AddedFiles)
		require.Equal(t, docVersion.ModifiedFiles, versionInfo.ModifiedFiles)
		require.Equal(t, docVersion.RemovedFiles, versionInfo.RemovedFiles)
	})

	t.Run("Returns error if no version info found", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		_, err := store.LatestDocumentVersion(ctx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestDeleteDocument(t *testing.T) {
	t.Run("Deletes document versions", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		doc1Version1 := populator.DocumentVersion()
		populator.DocumentVersion(map[string]any{
			"DocumentID": doc1Version1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})

		doc2Version := populator.DocumentVersion()

		// when
		err := store.DeleteDocument(ctx, doc1Version1.DocumentID)

		// then
		require.NoError(t, err)
		count, err := db.QueryRowAs[int](
			ctx,
			/* sql */ `select count(*) from docdb.document_version where document_id = $1`,
			doc1Version1.DocumentID,
		)
		require.NoError(t, err)
		require.Equal(t, 0, count)

		count, err = db.QueryRowAs[int](
			ctx,
			/* sql */ `select count(*) from docdb.document_version where document_id = $1`,
			doc2Version.DocumentID,
		)
		require.NoError(t, err)
		require.Equal(t, 1, count)
	})

	t.Run("Returns error if nothing to delete", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		err := store.DeleteDocument(ctx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})

	t.Run("In versions-exist mode verifies without deleting", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		docVersion := populator.DocumentVersion()

		// when: versions-exist mode must not delete, only confirm existence
		versionsExistCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		err := store.DeleteDocument(versionsExistCtx, docVersion.DocumentID)

		// then
		require.NoError(t, err)
		count, err := db.QueryRowAs[int](ctx,
			/* sql */ `select count(*) from docdb.document_version where document_id = $1`,
			docVersion.DocumentID,
		)
		require.NoError(t, err)
		require.Equal(t, 1, count) // still present, not deleted
	})

	t.Run("In versions-exist mode returns not found for a missing document", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		versionsExistCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		err := store.DeleteDocument(versionsExistCtx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestDeleteDocumentVersion(t *testing.T) {
	t.Run("Deletes document version", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		versionFile1 := populator.DocumentVersionFile(map[string]any{
			"Hash": docdb.ContentHash([]byte("b")),
		})
		versionFile2 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": versionFile1.DocumentVersion,
			"Hash":            docdb.ContentHash([]byte("a")),
		})

		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": versionFile1.DocumentVersion.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		versionFile3 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": docVersion2,
		})

		// when
		leftVersions, hashesToDelete, err := store.DeleteDocumentVersion(
			ctx,
			versionFile1.DocumentVersion.DocumentID,
			versionFile1.DocumentVersion.Version,
		)

		// then
		require.NoError(t, err)

		require.Equal(
			t,
			[]string{versionFile1.Hash, versionFile2.Hash},
			hashesToDelete,
		)
		require.Equal(
			t,
			[]docdb.VersionTime{versionFile3.DocumentVersion.Version},
			leftVersions,
		)
	})

	t.Run("Returns error if nothing to delete", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()

		// when
		_, _, err := store.DeleteDocumentVersion(ctx, docID, docdb.VersionTimeFrom(time.Now()))

		// then
		require.ErrorIs(t, err, docdb.NewErrDocumentNotFound(docID))
	})

	// Regression test for the two DeleteDocumentVersion fixes:
	//   - keep hashes still referenced by other versions (do not report them
	//     for deletion, otherwise the cascade wipes live blobs)
	//   - do not raise ErrDocumentNotFound when a successful delete frees no
	//     hashes (the carry-forward case where hashesToDelete is empty)
	t.Run("Keeps hashes shared with another version and does not error", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)

		sharedHash := docdb.ContentHash([]byte("shared content"))

		// version 1 with a single file
		versionFile1 := populator.DocumentVersionFile(map[string]any{
			"Name": "shared.pdf",
			"Hash": sharedHash,
		})

		// version 2 of the SAME document carries the same file (same hash) forward
		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": versionFile1.DocumentVersion.DocumentID,
			"CompanyID":  versionFile1.DocumentVersion.CompanyID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": docVersion2,
			"Name":            "shared.pdf",
			"Hash":            sharedHash,
		})

		// when: delete version 1, whose only file hash is still used by version 2
		leftVersions, hashesToDelete, err := store.DeleteDocumentVersion(
			ctx,
			versionFile1.DocumentVersion.DocumentID,
			versionFile1.DocumentVersion.Version,
		)

		// then
		require.NoError(t, err)
		require.Empty(t, hashesToDelete)
		require.Equal(t, []docdb.VersionTime{docVersion2.Version}, leftVersions)
	})

	t.Run("In versions-exist mode reports left versions and hashes without deleting", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		versionFile1 := populator.DocumentVersionFile(map[string]any{
			"Hash": docdb.ContentHash([]byte("b")),
		})
		versionFile2 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": versionFile1.DocumentVersion,
			"Hash":            docdb.ContentHash([]byte("a")),
		})
		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": versionFile1.DocumentVersion.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		versionFile3 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": docVersion2,
		})

		// when: versions-exist mode returns the same leftVersions/hashesToDelete a
		// real delete would, but must not delete the version row.
		versionsExistCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		leftVersions, hashesToDelete, err := store.DeleteDocumentVersion(
			versionsExistCtx,
			versionFile1.DocumentVersion.DocumentID,
			versionFile1.DocumentVersion.Version,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, []string{versionFile1.Hash, versionFile2.Hash}, hashesToDelete)
		require.Equal(t, []docdb.VersionTime{versionFile3.DocumentVersion.Version}, leftVersions)

		// the targeted version row must still be present
		count, err := db.QueryRowAs[int](ctx,
			/* sql */ `select count(*) from docdb.document_version where document_id = $1 and version = $2`,
			versionFile1.DocumentVersion.DocumentID,
			versionFile1.DocumentVersion.Version,
		)
		require.NoError(t, err)
		require.Equal(t, 1, count)
	})

	t.Run("In versions-exist mode returns not found for a missing version", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docID := uu.IDv7()

		// when
		versionsExistCtx := pgstore.ContextWithMetadataStoreVersionsExist(ctx)
		_, _, err := store.DeleteDocumentVersion(versionsExistCtx, docID, docdb.VersionTimeFrom(time.Now()))

		// then
		require.ErrorIs(t, err, docdb.NewErrDocumentNotFound(docID))
	})
}
