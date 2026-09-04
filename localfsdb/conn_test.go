package localfsdb_test

import (
	"context"
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"runtime"
	"slices"
	"sync"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"
	"github.com/ungerik/go-fs/uuiddir"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/localfsdb"
	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

func TestCreateDocument(t *testing.T) {
	var (
		conn             = localfsdb.NewTestConn(t)
		versionTime0     = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")
		defaultCompanyID = uu.IDFrom("2fc110fd-ed66-4a8f-9498-4dcb8386d300")
		defaultUserID    = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		defaultReason    = "TestCreateDocument"
	)
	type args struct {
		companyID uu.ID
		docID     uu.ID
		userID    uu.ID
		reason    string
		version   docdb.VersionTime
		files     []fs.FileReader
	}
	tests := []struct {
		name            string
		args            args
		wantVersionInfo *docdb.VersionInfo
		wantFiles       []fs.FileReader
		wantFinalErr    bool
		wantFinalErrAs  error
	}{
		{
			name:         "invalid input",
			args:         args{},
			wantFinalErr: true,
		},
		{
			// A document's first version must contain at least one file:
			// creating a document with no files is rejected, because a document
			// cannot start with an empty, change-less version.
			name: "create document without files is rejected",
			args: args{
				companyID: defaultCompanyID,
				docID:     uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171"),
				userID:    defaultUserID,
				reason:    defaultReason,
				version:   versionTime0,
				files:     nil,
			},
			wantFinalErr: true,
		},
		{
			name: "create document with 1 file",
			args: args{
				companyID: defaultCompanyID,
				docID:     uu.IDFrom("a3bf09b6-d2e4-400d-bdf1-fa0a63f934d1"),
				userID:    defaultUserID,
				reason:    defaultReason,
				version:   versionTime0,
				files:     newTestMemFiles("a.txt"),
			},
			wantVersionInfo: &docdb.VersionInfo{
				CompanyID:    defaultCompanyID,
				DocID:        uu.IDFrom("a3bf09b6-d2e4-400d-bdf1-fa0a63f934d1"),
				Version:      versionTime0,
				CommitUserID: defaultUserID,
				CommitReason: defaultReason,
				Files:        newTestFileInfos("a.txt"),
				AddedFiles:   []string{"a.txt"},
			},
			wantFiles: newTestMemFiles("a.txt"),
		},
		{
			name: "create document with 2 files",
			args: args{
				companyID: defaultCompanyID,
				docID:     uu.IDFrom("ba4260f6-18c7-4213-8afc-7d041ed7df8d"),
				userID:    defaultUserID,
				reason:    defaultReason,
				version:   versionTime0,
				files:     newTestMemFiles("a.txt", "b.txt"),
			},
			wantVersionInfo: &docdb.VersionInfo{
				CompanyID:    defaultCompanyID,
				DocID:        uu.IDFrom("ba4260f6-18c7-4213-8afc-7d041ed7df8d"),
				Version:      versionTime0,
				CommitUserID: defaultUserID,
				CommitReason: defaultReason,
				Files:        newTestFileInfos("a.txt", "b.txt"),
				AddedFiles:   []string{"a.txt", "b.txt"},
			},
			wantFiles: newTestMemFiles("a.txt", "b.txt"),
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var gotVersionInfo *docdb.VersionInfo
			err := conn.CreateDocument(
				t.Context(),
				tt.args.companyID,
				tt.args.docID,
				tt.args.userID,
				tt.args.reason,
				tt.args.version,
				tt.args.files,
				func(ctx context.Context, versionInfo *docdb.VersionInfo) error {
					gotVersionInfo = versionInfo
					return nil
				},
			)
			require.True(t, gotVersionInfo != nil && err == nil || gotVersionInfo == nil && err != nil)
			require.Equal(t, tt.wantVersionInfo, gotVersionInfo)
			if gotVersionInfo != nil {
				require.NoError(t, docdb.CheckConnDocumentVersionFiles(t.Context(), conn, tt.args.docID, gotVersionInfo.Version, tt.wantFiles))
			}
			if tt.wantFinalErrAs != nil {
				require.ErrorAs(t, err, tt.wantFinalErrAs)
				return
			}
			if tt.wantFinalErr {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
			gotCompanyID, err := conn.DocumentCompanyID(t.Context(), tt.args.docID)
			require.NoError(t, err)
			require.Equal(t, defaultCompanyID, gotCompanyID)
		})
	}
}

// TestAddDocumentVersion_RemoveAllFilesRejected verifies that a new version
// cannot remove every file of a document: at least one file must remain in
// every version.
func TestAddDocumentVersion_RemoveAllFilesRejected(t *testing.T) {
	conn := localfsdb.NewTestConn(t)
	companyID := uu.IDv4()
	docID := uu.IDv4()
	userID := uu.IDv4()
	v0 := docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")

	require.NoError(t, conn.CreateDocument(
		t.Context(), companyID, docID, userID, "init", v0,
		newTestMemFiles("a.txt"), noopOnNew,
	))

	// Removing the only file would leave the new version with zero files.
	err := conn.AddDocumentVersion(
		t.Context(), docID, userID, "remove all files",
		docdb.CreateVersionRemoveFiles("a.txt"),
		noopOnNew,
	)
	require.Error(t, err)
	require.NotErrorIs(t, err, docdb.ErrNoChanges) // a distinct error, not no-change
	require.ErrorContains(t, err, "at least one file")
}

func TestAddDocumentVersion(t *testing.T) {
	var (
		conn             = localfsdb.NewTestConn(t)
		versionTime0     = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")
		versionTime1     = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.001")
		versionTime2     = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.002")
		versionTime3     = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.003")
		defaultCompanyID = uu.IDFrom("a5739df8-5351-4d46-ac80-49ac41e058f4")
		defaultUserID    = uu.IDFrom("ae7d5785-0a20-4745-b179-ca48ec81b493")
		createReason     = "TestAddDocumentVersion->Create first version"
		testError1       = errors.New("testError1")
		testError2       = errors.New("testError2")
	)
	type args struct {
		docID         uu.ID
		userID        uu.ID
		reason        string
		createVersion docdb.CreateVersionFunc
	}
	type call struct {
		args                  args
		onNewVersionResultErr error
		wantVersionInfo       *docdb.VersionInfo
		wantFiles             []fs.FileReader
	}
	tests := []struct {
		name            string
		createCompanyID uu.ID
		createDocID     uu.ID
		createUserID    uu.ID
		createReason    string
		createVersion   docdb.VersionTime
		createFiles     []fs.FileReader
		calls           []call
		wantFinalErr    bool
		wantFinalErrIs  error
		wantFinalErrAs  error
	}{
		{
			name:            "invalid call",
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("a920f1ab-f150-4455-96ec-af3747f0fa78"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createVersion:   versionTime0,
			createFiles:     newTestMemFiles("a.txt"),
			calls:           []call{{}},
			wantFinalErr:    true,
		},
		{
			name:            "createVersion returns error",
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("142f465b-bc8b-4285-aed8-21917c924e47"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createVersion:   versionTime0,
			createFiles:     newTestMemFiles("a.txt"),
			calls: []call{
				{
					args: args{
						docID:  uu.IDFrom("142f465b-bc8b-4285-aed8-21917c924e47"),
						userID: defaultUserID,
						reason: "second version",
						createVersion: func(ctx context.Context, docID uu.ID, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
							return nil, testError1
						},
					},
					onNewVersionResultErr: nil,
				},
			},
			wantFinalErrIs: testError1,
		},
		{
			name:            "no changes",
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("cae28b7d-1b76-4fe3-b362-758f88396239"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createVersion:   versionTime0,
			createFiles:     newTestMemFiles("a.txt"),
			calls: []call{
				{
					args: args{
						docID:  uu.IDFrom("cae28b7d-1b76-4fe3-b362-758f88396239"),
						userID: defaultUserID,
						reason: "second version",
						createVersion: func(ctx context.Context, docID uu.ID, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
							return &docdb.CreateVersionResult{Version: versionTime1}, nil
						},
					},
					onNewVersionResultErr: nil,
				},
			},
			wantFinalErrIs: docdb.ErrNoChanges,
		},
		{
			name:            "write identical file",
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("21dc078a-b930-42ae-b4f6-6b8bea86050e"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createVersion:   versionTime0,
			createFiles:     newTestMemFiles("a.txt"),
			calls: []call{
				{
					args: args{
						docID:  uu.IDFrom("21dc078a-b930-42ae-b4f6-6b8bea86050e"),
						userID: defaultUserID,
						reason: "second version",
						createVersion: func(ctx context.Context, docID uu.ID, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
							return &docdb.CreateVersionResult{Version: versionTime1, WriteFiles: newTestMemFiles("a.txt")}, nil
						},
					},
					onNewVersionResultErr: nil,
					wantVersionInfo:       nil,
					wantFiles:             nil,
				},
			},
			wantFinalErrIs: docdb.ErrNoChanges,
		},
		{
			name:            "change 1 file",
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createVersion:   versionTime0,
			createFiles:     newTestMemFiles("a.txt"),
			calls: []call{
				{
					args: args{
						docID:  uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						userID: defaultUserID,
						reason: "second version",
						createVersion: func(ctx context.Context, docID uu.ID, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
							return &docdb.CreateVersionResult{
								Version:    versionTime1,
								WriteFiles: []fs.FileReader{fs.NewMemFile("a.txt", []byte("CHANGED"))},
							}, nil
						},
					},
					onNewVersionResultErr: nil,
					wantVersionInfo: &docdb.VersionInfo{
						CompanyID:     defaultCompanyID,
						DocID:         uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						Version:       versionTime1,
						PrevVersion:   &versionTime0,
						CommitUserID:  defaultUserID,
						CommitReason:  "second version",
						Files:         map[string]docdb.FileInfo{"a.txt": newFileInfo("a.txt", []byte("CHANGED"))},
						AddedFiles:    nil,
						RemovedFiles:  nil,
						ModifiedFiles: []string{"a.txt"},
					},
					wantFiles: []fs.FileReader{fs.NewMemFile("a.txt", []byte("CHANGED"))},
				},
				{
					args: args{
						docID:  uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						userID: defaultUserID,
						reason: "third version",
						createVersion: func(ctx context.Context, docID uu.ID, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
							return &docdb.CreateVersionResult{
								Version:    versionTime2,
								WriteFiles: []fs.FileReader{fs.NewMemFile("a.txt", []byte("CHANGED AGAIN"))},
							}, nil
						},
					},
					onNewVersionResultErr: nil,
					wantVersionInfo: &docdb.VersionInfo{
						CompanyID:     defaultCompanyID,
						DocID:         uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						Version:       versionTime2,
						PrevVersion:   &versionTime1,
						CommitUserID:  defaultUserID,
						CommitReason:  "third version",
						Files:         map[string]docdb.FileInfo{"a.txt": newFileInfo("a.txt", []byte("CHANGED AGAIN"))},
						AddedFiles:    nil,
						RemovedFiles:  nil,
						ModifiedFiles: []string{"a.txt"},
					},
					wantFiles: []fs.FileReader{fs.NewMemFile("a.txt", []byte("CHANGED AGAIN"))},
				},
				{
					args: args{
						docID:  uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						userID: defaultUserID,
						reason: "fourth version",
						createVersion: func(ctx context.Context, docID uu.ID, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
							newCompanyID := uu.IDMust("32b72879-b489-4d5d-9187-eba8127cc168")
							return &docdb.CreateVersionResult{
								Version:      versionTime3,
								WriteFiles:   newTestMemFiles("b.txt"),
								RemoveFiles:  []string{"a.txt"},
								NewCompanyID: uu.NullableID(newCompanyID),
							}, nil
						},
					},
					onNewVersionResultErr: nil,
					wantVersionInfo: &docdb.VersionInfo{
						CompanyID:     uu.IDMust("32b72879-b489-4d5d-9187-eba8127cc168"),
						DocID:         uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						Version:       versionTime3,
						PrevVersion:   &versionTime2,
						CommitUserID:  defaultUserID,
						CommitReason:  "fourth version",
						Files:         newTestFileInfos("b.txt"),
						AddedFiles:    []string{"b.txt"},
						RemovedFiles:  []string{"a.txt"},
						ModifiedFiles: nil,
					},
					wantFiles: newTestMemFiles("b.txt"),
				},
			},
		},
		{
			name:            "file in both WriteFiles and RemoveFiles",
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("d8c4e0a7-2f3b-4a91-b5d6-1e7f8c9a0b2d"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createVersion:   versionTime0,
			createFiles:     newTestMemFiles("a.txt"),
			calls: []call{
				{
					args: args{
						docID:  uu.IDFrom("d8c4e0a7-2f3b-4a91-b5d6-1e7f8c9a0b2d"),
						userID: defaultUserID,
						reason: "second version",
						createVersion: func(ctx context.Context, docID uu.ID, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
							return &docdb.CreateVersionResult{
								Version:     versionTime1,
								WriteFiles:  []fs.FileReader{fs.NewMemFile("a.txt", []byte("CHANGED"))},
								RemoveFiles: []string{"a.txt"},
							}, nil
						},
					},
				},
			},
			wantFinalErr: true,
		},
		{
			name:            "onNewVersion returns error",
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("0a007614-c66c-4af5-97ba-337c32ae2bc2"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createVersion:   versionTime0,
			createFiles:     newTestMemFiles("a.txt"),
			calls: []call{
				{
					args: args{
						docID:  uu.IDFrom("0a007614-c66c-4af5-97ba-337c32ae2bc2"),
						userID: defaultUserID,
						reason: "second version",
						createVersion: func(ctx context.Context, docID uu.ID, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
							return &docdb.CreateVersionResult{
								Version:    versionTime1,
								WriteFiles: newTestMemFiles("b.txt"),
							}, nil
						},
					},
					onNewVersionResultErr: testError2,
					wantVersionInfo:       nil,
					wantFiles:             nil,
				},
			},
			wantFinalErrIs: testError2,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var lastVersionInfo *docdb.VersionInfo
			err := conn.CreateDocument(
				t.Context(),
				tt.createCompanyID,
				tt.createDocID,
				tt.createUserID,
				tt.createReason,
				tt.createVersion,
				tt.createFiles,
				func(ctx context.Context, versionInfo *docdb.VersionInfo) error {
					lastVersionInfo = versionInfo
					return nil
				},
			)
			require.NoError(t, err)
			require.Equal(t, versionTime0, lastVersionInfo.Version)

			for i, call := range tt.calls {
				var gotVersionInfo *docdb.VersionInfo
				err = conn.AddDocumentVersion(
					t.Context(),
					call.args.docID,
					call.args.userID,
					call.args.reason,
					call.args.createVersion,
					func(ctx context.Context, versionInfo *docdb.VersionInfo) error {
						gotVersionInfo = versionInfo
						return call.onNewVersionResultErr
					},
				)
				// Only last call error is compared with wantFinalErrAs
				// all calls before that must not return an error
				if i < len(tt.calls)-1 {
					require.NoError(t, err)
				}
				if err != nil {
					continue // No further checks after error because other results are undefined
				}
				require.NotNil(t, gotVersionInfo, "version info must not be nil when error is nil")
				require.Equal(t, call.wantVersionInfo, gotVersionInfo)
				if gotVersionInfo != nil {
					require.NoError(t, docdb.CheckConnDocumentVersionFiles(t.Context(), conn, call.args.docID, gotVersionInfo.Version, call.wantFiles))
				}
			}
			if tt.wantFinalErrIs != nil {
				require.ErrorIs(t, err, tt.wantFinalErrIs)
				return
			}
			if tt.wantFinalErrAs != nil {
				require.ErrorAs(t, err, tt.wantFinalErrAs)
				return
			}
			if tt.wantFinalErr {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
		})
	}
}

func TestRestoreDocument(t *testing.T) {
	var (
		ctx         = t.Context()
		companyID   = uu.IDFrom("3a4f1c2e-7b8d-4e9a-b1c2-d3e4f5a6b7c8")
		otherCompID = uu.IDFrom("9f8e7d6c-5b4a-4210-bedc-ba9876543210")
		docID       = uu.IDFrom("11111111-2222-4333-8444-555555555555")
		userID      = uu.IDFrom("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
		version0    = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
		version1    = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.001")
		version2    = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.002")
	)

	setup := func(t *testing.T) (*localfsdb.Conn, *docdb.HashedDocument) {
		t.Helper()
		conn := localfsdb.NewTestConn(t)
		require.NoError(t, conn.CreateDocument(
			ctx, companyID, docID, userID, "v0",
			version0, newTestMemFiles("a.txt"),
			noopOnNew,
		))
		require.NoError(t, conn.AddDocumentVersion(
			ctx, docID, userID, "v1",
			func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
				return &docdb.CreateVersionResult{
					Version:    version1,
					WriteFiles: newTestMemFiles("b.txt"),
				}, nil
			},
			noopOnNew,
		))
		require.NoError(t, conn.AddDocumentVersion(
			ctx, docID, userID, "v2",
			func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
				return &docdb.CreateVersionResult{
					Version:     version2,
					RemoveFiles: []string{"a.txt"},
				}, nil
			},
			noopOnNew,
		))
		backup, err := docdb.ReadHashedDocument(ctx, conn, docID)
		require.NoError(t, err)
		return conn, backup
	}

	assertMatches := func(t *testing.T, target docdb.Conn, backup *docdb.HashedDocument) {
		t.Helper()
		got, err := docdb.ReadHashedDocument(ctx, target, backup.ID)
		require.NoError(t, err)
		require.Equal(t, backup.ID, got.ID)
		require.Equal(t, backup.CompanyID, got.CompanyID)
		require.Equal(t, backup.HashedFiles, got.HashedFiles)
		require.Equal(t, len(backup.Versions), len(got.Versions))
		for v, hv := range backup.Versions {
			gotHV, ok := got.Versions[v]
			require.True(t, ok, "version %s missing", v)
			require.Equal(t, hv.CommitUserID, gotHV.CommitUserID)
			require.Equal(t, hv.CommitReason, gotHV.CommitReason)
			require.Equal(t, hv.FileHashes, gotHV.FileHashes)
		}
	}

	t.Run("recreate=true on fresh conn", func(t *testing.T) {
		_, backup := setup(t)
		target := localfsdb.NewTestConn(t)
		require.NoError(t, target.RestoreDocument(ctx, backup, true))
		assertMatches(t, target, backup)
	})

	t.Run("recreate=false on fresh conn", func(t *testing.T) {
		_, backup := setup(t)
		target := localfsdb.NewTestConn(t)
		require.NoError(t, target.RestoreDocument(ctx, backup, false))
		assertMatches(t, target, backup)
	})

	t.Run("recreate=true replaces modified existing", func(t *testing.T) {
		target, backup := setup(t)
		_, err := target.DeleteDocumentVersion(ctx, docID, version1)
		require.NoError(t, err)
		require.NoError(t, target.RestoreDocument(ctx, backup, true))
		assertMatches(t, target, backup)
	})

	t.Run("recreate=false fills in missing version, keeps existing", func(t *testing.T) {
		target, backup := setup(t)
		_, err := target.DeleteDocumentVersion(ctx, docID, version1)
		require.NoError(t, err)
		require.NoError(t, target.RestoreDocument(ctx, backup, false))
		assertMatches(t, target, backup)
	})

	t.Run("recreate=false fills in missing earliest version with correct metadata", func(t *testing.T) {
		target, backup := setup(t)
		// Delete the earliest version so restore must re-add it as the first
		// version of the document, with no predecessor.
		_, err := target.DeleteDocumentVersion(ctx, docID, version0)
		require.NoError(t, err)
		require.NoError(t, target.RestoreDocument(ctx, backup, false))
		assertMatches(t, target, backup)

		// The restored earliest version must be diffed against nothing, not
		// against a later on-disk version. assertMatches recomputes diffs, so
		// it cannot catch a corrupt stored VersionInfo — check it directly.
		info, err := target.DocumentVersionInfo(ctx, docID, version0)
		require.NoError(t, err)
		require.Nil(t, info.PrevVersion)
		require.Equal(t, []string{"a.txt"}, info.AddedFiles)
		require.Empty(t, info.ModifiedFiles)
		require.Empty(t, info.RemovedFiles)
	})

	t.Run("recreate=false skips already-present versions", func(t *testing.T) {
		target, backup := setup(t)
		// All versions present — restore should be a no-op.
		require.NoError(t, target.RestoreDocument(ctx, backup, false))
		assertMatches(t, target, backup)
	})

	t.Run("recreate=false errors on companyID mismatch", func(t *testing.T) {
		target, backup := setup(t)
		backup.CompanyID = otherCompID
		err := target.RestoreDocument(ctx, backup, false)
		require.Error(t, err)
	})

	t.Run("rejects invalid HashedDocument", func(t *testing.T) {
		target := localfsdb.NewTestConn(t)
		err := target.RestoreDocument(ctx, &docdb.HashedDocument{}, true)
		require.Error(t, err)
	})
}

func TestCompanyIDs(t *testing.T) {
	ctx := t.Context()
	conn := localfsdb.NewTestConn(t)
	userID := uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
	version := docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")

	t.Run("returns nil when no documents exist", func(t *testing.T) {
		companyIDs, err := conn.CompanyIDs(ctx)
		require.NoError(t, err)
		require.Nil(t, companyIDs)
	})

	t.Run("returns all companies sorted by ID", func(t *testing.T) {
		companyA := uu.IDFrom("11111111-1111-4111-8111-111111111111")
		companyB := uu.IDFrom("22222222-2222-4222-8222-222222222222")
		companyC := uu.IDFrom("33333333-3333-4333-8333-333333333333")
		// Create companies out of sorted order; companyB gets two documents to
		// prove each company is reported once regardless of document count.
		create := func(companyID uu.ID) {
			require.NoError(t, conn.CreateDocument(
				ctx, companyID, uu.IDv7(), userID, "init", version,
				newTestMemFiles("a.txt"), noopOnNew,
			))
		}
		create(companyC)
		create(companyA)
		create(companyB)
		create(companyB)

		companyIDs, err := conn.CompanyIDs(ctx)
		require.NoError(t, err)
		require.Equal(t, uu.IDSlice{companyA, companyB, companyC}, companyIDs)
	})
}

func TestCompanyDocumentIDs(t *testing.T) {
	ctx := t.Context()
	conn := localfsdb.NewTestConn(t)
	userID := uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
	version := docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")

	t.Run("returns nil for company without documents", func(t *testing.T) {
		// The company directory never existed, so enumeration must not error.
		docIDs, err := conn.CompanyDocumentIDs(ctx, uu.IDv7())
		require.NoError(t, err)
		require.Nil(t, docIDs)
	})

	t.Run("returns all documents sorted by ID", func(t *testing.T) {
		companyID := uu.IDFrom("6f296458-24cd-4146-ac3a-33ca885a993e")
		idA := uu.IDFrom("11111111-1111-4111-8111-111111111111")
		idB := uu.IDFrom("22222222-2222-4222-8222-222222222222")
		idC := uu.IDFrom("33333333-3333-4333-8333-333333333333")
		// Create out of sorted order to prove the result is sorted by ID.
		for _, docID := range []uu.ID{idC, idA, idB} {
			require.NoError(t, conn.CreateDocument(
				ctx, companyID, docID, userID, "init", version,
				newTestMemFiles("a.txt"), noopOnNew,
			))
		}
		// A document of a different company must not be included.
		otherCompanyID := uu.IDFrom("9f8e7d6c-5b4a-4210-bedc-ba9876543210")
		require.NoError(t, conn.CreateDocument(
			ctx, otherCompanyID, uu.IDv7(), userID, "init", version,
			newTestMemFiles("a.txt"), noopOnNew,
		))

		docIDs, err := conn.CompanyDocumentIDs(ctx, companyID)
		require.NoError(t, err)
		require.Equal(t, uu.IDSlice{idA, idB, idC}, docIDs)
	})
}

// newTestConnDirs returns a conn over a fresh temp dir together with its two
// top-level directories, which localfsdb.NewTestConn does not expose. Tests that
// assert on the on-disk layout need them to build uuiddir paths.
func newTestConnDirs(t *testing.T) (conn *localfsdb.Conn, documentsDir, companiesDir fs.File) {
	t.Helper()
	tmp := fs.File(t.TempDir())
	documentsDir = tmp.Join("documents")
	companiesDir = tmp.Join("companies")
	require.NoError(t, documentsDir.MakeDir())
	require.NoError(t, companiesDir.MakeDir())
	return localfsdb.NewConn(documentsDir, companiesDir), documentsDir, companiesDir
}

// noopOnNew is the docdb.OnNewVersionFunc for a test that does not care about
// the callback.
func noopOnNew(context.Context, *docdb.VersionInfo) error { return nil }

func newTestMemFiles(filenames ...string) []fs.FileReader {
	files := make([]fs.FileReader, len(filenames))
	for i, filename := range filenames {
		files[i] = fs.NewMemFile(filename, []byte(filename)) // Use filename as content
	}
	return files
}

func newTestFileInfos(filenames ...string) map[string]docdb.FileInfo {
	infos := make(map[string]docdb.FileInfo, len(filenames))
	for _, filename := range filenames {
		// Use filename as content
		infos[filename] = docdb.FileInfo{
			Name: filename,
			Size: int64(len(filename)),
			Hash: docdb.ContentHash([]byte(filename)),
		}
	}
	return infos
}

func newFileInfo(filename string, data []byte) docdb.FileInfo {
	return docdb.FileInfo{
		Name: filename,
		Size: int64(len(data)),
		Hash: docdb.ContentHash(data),
	}
}

// func equalInfoWithoutVersionTime(a, b *docdb.VersionInfo) bool {
// 	if a == b {
// 		return true
// 	}
// 	if a == nil || b == nil {
// 		return false
// 	}
// 	return a.DocID == b.DocID &&
// 		a.CommitUserID == b.CommitUserID &&
// 		a.CommitReason == b.CommitReason &&
// 		maps.Equal(a.Files, b.Files) &&
// 		slices.Equal(a.AddedFiles, b.AddedFiles) &&
// 		slices.Equal(a.RemovedFiles, b.RemovedFiles) &&
// 		slices.Equal(a.ModifiedFiles, b.ModifiedFiles)
// }

func TestCreateDocument_PathConflict(t *testing.T) {
	// given a fresh localfsdb conn and an orphan regular file planted at one
	// of the UUID-split path components under companies/{companyID}/
	conn, _, companiesDir := newTestConnDirs(t)

	var (
		companyID = uu.IDFrom("6f296458-24cd-4146-ac3a-33ca885a993e")
		docID     = uu.IDFrom("c538ac93-2cf0-49a9-8378-22cd48b5ab84")
		userID    = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		version   = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")
	)

	// Plant a regular file at companies/{companyID}/c5/38a/c93/2cf049a9
	// (the 4th UUID-split level of docID c538ac93-2cf0-49a9-8378-22cd48b5ab84,
	// which would normally be a directory). This mirrors the on-disk state
	// that produces "file already exists" errors in production.
	orphanParent := companiesDir.Join(companyID.String(), "c5", "38a", "c93")
	require.NoError(t, orphanParent.MakeAllDirs())
	orphanContent := []byte("orphan regular file")
	require.NoError(t, orphanParent.Join("2cf049a9").WriteAll(orphanContent))

	// when CreateDocument runs against that state
	err := conn.CreateDocument(
		t.Context(),
		companyID,
		docID,
		userID,
		"TestCreateDocument_PathConflict",
		version,
		newTestMemFiles("a.txt"),
		func(ctx context.Context, vi *docdb.VersionInfo) error { return nil },
	)

	// then the returned error matches os.ErrExist and is unwrappable as
	// docdb.ErrPathConflict carrying the offending path's details
	require.Error(t, err)
	require.ErrorIs(t, err, os.ErrExist)

	var conflict docdb.ErrPathConflict
	require.ErrorAs(t, err, &conflict)
	require.Equal(t, docID, conflict.DocID())
	require.Equal(t, companyID, conflict.CompanyID())
	require.Equal(t, "regular file", conflict.EntryType())
	require.Equal(t, int64(len(orphanContent)), conflict.Size())
	require.Contains(t, conflict.ConflictPath(), "/c5/38a/c93/2cf049a9")
}

// TestCreateDocument_ConcurrentSharedPathPrefix exercises the TOCTOU race
// inside [fs.File.MakeAllDirs] that surfaces in production as a "file
// already exists" error on what's actually a valid (empty) directory.
//
// Scenario: many email-import attachments processed in parallel against
// the same company. Each gets a fresh UUIDv7 docID, but adjacent IDs
// share the time-prefix bits, so their uuiddir paths overlap at multiple
// upper levels. Two goroutines concurrently calling MakeAllDirs on
// sibling leaf paths race on creating the shared intermediate
// directories; the loser sees os.Mkdir EEXIST and (pre-fix) returns
// [fs.ErrAlreadyExists] even though the path is now a valid directory.
//
// The fix in [fs.File.MakeDir] re-stats the path on EEXIST and treats
// "exists as a directory" as success (compatible with os.MkdirAll). This
// test runs N concurrent CreateDocument calls with manually-constructed
// docIDs that share the first 16 hex chars (= the first 4 uuiddir levels)
// and asserts that all succeed.
func TestCreateDocument_ConcurrentSharedPathPrefix(t *testing.T) {
	const (
		concurrency = 32
		// All docIDs share these first 16 hex chars (the 4-level uuiddir
		// prefix); the last 16 hex chars vary per goroutine.
		sharedPrefix = "c538ac932cf049a9"
	)

	conn := localfsdb.NewTestConn(t)
	companyID := uu.IDFrom("6f296458-24cd-4146-ac3a-33ca885a993e")
	userID := uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
	version := docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")

	// given a set of docIDs sharing the first 4 uuiddir levels
	docIDs := make([]uu.ID, concurrency)
	for i := range docIDs {
		suffix := fmt.Sprintf("%016x", uint64(i+1)<<48|0xab)
		raw := sharedPrefix + suffix
		var b [16]byte
		for j := range b {
			_, err := fmt.Sscanf(raw[2*j:2*j+2], "%x", &b[j])
			require.NoError(t, err)
		}
		id, err := uu.IDFromBytes(b[:])
		require.NoError(t, err)
		docIDs[i] = id
	}

	// when each docID is created concurrently for the same company
	var (
		wg    sync.WaitGroup
		mu    sync.Mutex
		errs  []error
		ready = make(chan struct{})
	)
	wg.Add(concurrency)
	for _, id := range docIDs {
		go func(docID uu.ID) {
			defer wg.Done()
			<-ready
			err := conn.CreateDocument(
				t.Context(),
				companyID,
				docID,
				userID,
				"TestCreateDocument_ConcurrentSharedPathPrefix",
				version,
				newTestMemFiles("a.txt"),
				func(ctx context.Context, vi *docdb.VersionInfo) error { return nil },
			)
			if err != nil {
				mu.Lock()
				errs = append(errs, fmt.Errorf("docID %s: %w", docID, err))
				mu.Unlock()
			}
		}(id)
	}
	close(ready)
	wg.Wait()

	// then every CreateDocument call must succeed; without the race fix,
	// some goroutines hit "file already exists" on a shared intermediate dir
	require.Empty(t, errs, "concurrent CreateDocument with shared path prefix produced errors")

	// and every doc must be readable back through the conn
	for _, id := range docIDs {
		gotCompanyID, err := conn.DocumentCompanyID(t.Context(), id)
		require.NoError(t, err, "doc %s not readable after create", id)
		require.Equal(t, companyID, gotCompanyID, "doc %s mapped to wrong company", id)
	}
}

// TestVersionDirWithHiddenFiles covers a version directory polluted with files
// that no version info tracks: a .DS_Store left by a Finder visit, the temp
// file of an interrupted rsync, an NFS silly-rename. Such a file must not be
// reported as a file of the version — otherwise every reader of the document
// fails, and a bulk operation over a whole company aborts on it.
func TestVersionDirWithHiddenFiles(t *testing.T) {
	// given a document with one version
	conn, documentsDir, _ := newTestConnDirs(t)

	var (
		companyID  = uu.IDFrom("6f296458-24cd-4146-ac3a-33ca885a993e")
		docID      = uu.IDFrom("c538ac93-2cf0-49a9-8378-22cd48b5ab84")
		userID     = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		v0         = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")
		newVersion *docdb.VersionInfo
	)
	require.NoError(t, conn.CreateDocument(
		t.Context(), companyID, docID, userID, "TestVersionDirWithHiddenFiles", v0,
		newTestMemFiles("a.txt"), noopOnNew,
	))

	// when hidden files and a sub-directory appear in the version directory
	versionDir := uuiddir.Join(documentsDir, docID).Join(v0.String())
	require.True(t, versionDir.IsDir())
	require.NoError(t, versionDir.Join(".DS_Store").WriteAllString("Finder cruft"))
	require.NoError(t, versionDir.Join(".a.txt.4Xk9pQ").WriteAllString("interrupted rsync"))
	require.NoError(t, versionDir.Join("subdir").MakeDir())

	// then they are not files of the version
	fileProvider, err := conn.DocumentVersionFileProvider(t.Context(), docID, v0)
	require.NoError(t, err)
	filenames, err := fileProvider.ListFiles(t.Context())
	require.NoError(t, err)
	require.Equal(t, []string{"a.txt"}, filenames)

	// and the document is still readable as a whole
	doc, err := docdb.ReadHashedDocument(t.Context(), conn, docID)
	require.NoError(t, err)
	versions := doc.VersionTimes()
	require.Len(t, versions, 1)
	require.Equal(t, []string{"a.txt"}, slices.Sorted(maps.Keys(doc.Versions[versions[0]].FileHashes)))

	// and a new version neither adopts them nor reports them as removed
	require.NoError(t, conn.AddDocumentVersion(
		t.Context(), docID, userID, "add b.txt",
		docdb.CreateVersionWriteFiles(newTestMemFiles("b.txt")...),
		docdb.CaptureNewVersionInfo(&newVersion),
	))
	require.Equal(t, []string{"a.txt", "b.txt"}, slices.Sorted(maps.Keys(newVersion.Files)))
	require.Equal(t, []string{"b.txt"}, newVersion.AddedFiles)
	require.Empty(t, newVersion.ModifiedFiles)
	require.Empty(t, newVersion.RemovedFiles)
}

// panicFileReader is an fs.FileReader whose content cannot be read: every read
// path panics. Copying it into the new version directory is the last thing
// CreateDocument and AddDocumentVersion do before they have a complete version
// on disk, so it panics them at the point where the document or version
// directory exists but nothing that makes it valid has been written yet.
type panicFileReader struct {
	fs.FileReader
}

func newPanicFileReader(name string) fs.FileReader {
	return panicFileReader{FileReader: fs.NewMemFile(name, []byte(name))}
}

func (panicFileReader) ReadAll() ([]byte, error) { panic("file reader blew up") }

func (panicFileReader) ReadAllContext(context.Context) ([]byte, error) {
	panic("file reader blew up")
}

func (panicFileReader) ReadAllContentHash(context.Context) ([]byte, string, error) {
	panic("file reader blew up")
}

func (panicFileReader) WriteTo(io.Writer) (int64, error) { panic("file reader blew up") }

func (panicFileReader) OpenReader() (fs.ReadCloser, error) { panic("file reader blew up") }

// TestCreateDocument_RollsBackOnPanic and TestAddDocumentVersion_RollsBackOnPanic
// are regression tests for the rollback defers keying on the named error result,
// which a panic never sets.
//
// A panic that escapes leaves the half-created document or version on disk: a
// document directory with no version info JSON, or a version directory the
// document's version list does not know about. Both make every later reader of
// that document fail, and neither is repaired by retrying the call — the
// document then already exists. The panic has to reach the rollback as an
// error, which is what deferring errs.RecoverPanicAsError after the rollback
// (so it runs before it) does. Calling recover from inside the rollback closure
// would not: recover only recovers when the deferred function calls it itself.
func TestCreateDocument_RollsBackOnPanic(t *testing.T) {
	// given a conn with no document
	conn, documentsDir, companiesDir := newTestConnDirs(t)

	var (
		companyID = uu.IDFrom("6f296458-24cd-4146-ac3a-33ca885a993e")
		docID     = uu.IDFrom("c538ac93-2cf0-49a9-8378-22cd48b5ab84")
		userID    = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		v0        = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")
	)

	// when creating it panics while writing the version's files
	err := conn.CreateDocument(
		t.Context(), companyID, docID, userID, "TestCreateDocument_RollsBackOnPanic", v0,
		[]fs.FileReader{newPanicFileReader("a.txt")}, noopOnNew,
	)

	// then the panic is returned as an error rather than escaping
	require.ErrorContains(t, err, "file reader blew up")

	// and nothing of the half-created document is left behind: neither the
	// document directory nor the company's reference to it.
	require.False(t, uuiddir.Join(documentsDir, docID).Exists(),
		"the document directory created before the panic must be rolled back")
	require.False(t, uuiddir.Join(companiesDir.Join(companyID.String()), docID).Exists(),
		"the company document directory created before the panic must be rolled back")

	// and the document can still be created afterwards, which a leftover
	// directory would refuse as ErrDocumentAlreadyExists.
	require.NoError(t, conn.CreateDocument(
		t.Context(), companyID, docID, userID, "retry after panic", v0,
		newTestMemFiles("a.txt"), noopOnNew,
	))
}

func TestAddDocumentVersion_RollsBackOnPanic(t *testing.T) {
	// given a document with one version
	conn := localfsdb.NewTestConn(t)

	var (
		companyID = uu.IDFrom("6f296458-24cd-4146-ac3a-33ca885a993e")
		docID     = uu.IDFrom("c538ac93-2cf0-49a9-8378-22cd48b5ab84")
		userID    = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		v0        = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")
	)
	require.NoError(t, conn.CreateDocument(
		t.Context(), companyID, docID, userID, "TestAddDocumentVersion_RollsBackOnPanic", v0,
		newTestMemFiles("a.txt"), noopOnNew,
	))

	// when adding a version panics while writing its files
	err := conn.AddDocumentVersion(
		t.Context(), docID, userID, "add b.txt",
		docdb.CreateVersionWriteFiles(newPanicFileReader("b.txt")),
		noopOnNew,
	)

	// then the panic is returned as an error rather than escaping
	require.ErrorContains(t, err, "file reader blew up")

	// and the document is left at the version it had before the call: the
	// half-written version directory is gone, so no reader sees a version the
	// document's version list does not know about.
	versions, err := conn.DocumentVersions(t.Context(), docID)
	require.NoError(t, err)
	require.Equal(t, []docdb.VersionTime{v0}, versions)

	doc, err := docdb.ReadHashedDocument(t.Context(), conn, docID)
	require.NoError(t, err)
	require.Equal(t, []docdb.VersionTime{v0}, doc.VersionTimes())
	require.Equal(t, []string{"a.txt"}, slices.Sorted(maps.Keys(doc.Versions[v0].FileHashes)))

	// and a later version can still be added on top of v0
	var newVersion *docdb.VersionInfo
	require.NoError(t, conn.AddDocumentVersion(
		t.Context(), docID, userID, "add b.txt after panic",
		docdb.CreateVersionWriteFiles(newTestMemFiles("b.txt")...),
		docdb.CaptureNewVersionInfo(&newVersion),
	))
	require.Equal(t, []string{"a.txt", "b.txt"}, slices.Sorted(maps.Keys(newVersion.Files)))
}

// TestCreateDocumentHiddenFilesOnlyRejected covers the gap between the files a
// caller passes and the files the created version actually tracks.
//
// CreateDocument rejects a call with no files, because a document cannot start
// with an empty, change-less version. But the version's file list is built by
// enumerating the written directory through docdb.DirFileProvider, which does
// not report hidden entries as files of a version — so a caller passing only
// hidden files passed the len(files) check and produced exactly the version
// that check exists to reject: created without error, tracking nothing, and
// reading back empty through every reader of the document. The check has to be
// on the resulting file set, as it already is in AddDocumentVersion.
func TestCreateDocumentHiddenFilesOnlyRejected(t *testing.T) {
	conn := localfsdb.NewTestConn(t)

	var (
		companyID = uu.IDFrom("6f296458-24cd-4146-ac3a-33ca885a993e")
		docID     = uu.IDFrom("c538ac93-2cf0-49a9-8378-22cd48b5ab84")
		userID    = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		v0        = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")
	)

	// given a document whose files are all hidden
	err := conn.CreateDocument(
		t.Context(), companyID, docID, userID, "hidden files only", v0,
		[]fs.FileReader{
			fs.NewMemFile(".env", []byte("SECRET=1")),
			fs.NewMemFile(".DS_Store", []byte("Finder cruft")),
		},
		noopOnNew,
	)

	// then the document is not created
	require.ErrorContains(t, err, "has no files")
	exists, existsErr := conn.DocumentExists(t.Context(), docID)
	require.NoError(t, existsErr)
	require.False(t, exists, "a rejected CreateDocument must leave no document behind")

	// and a document with one tracked file among hidden ones is still created,
	// tracking only the file the version has
	var newVersion *docdb.VersionInfo
	require.NoError(t, conn.CreateDocument(
		t.Context(), companyID, docID, userID, "one tracked file", v0,
		[]fs.FileReader{
			fs.NewMemFile(".env", []byte("SECRET=1")),
			fs.NewMemFile("invoice.pdf", []byte("invoice")),
		},
		docdb.CaptureNewVersionInfo(&newVersion),
	))
	require.Equal(t, []string{"invoice.pdf"}, slices.Sorted(maps.Keys(newVersion.Files)))
	require.Equal(t, []string{"invoice.pdf"}, newVersion.AddedFiles)
}

// TestRestoreDocumentHiddenFilesOnlyRejected covers the third path that builds a
// version's file set by enumerating a directory it just wrote. CreateDocument
// and AddDocumentVersion both refuse a version that ends up tracking nothing,
// and RestoreDocument is the path most likely to be handed such a version: the
// filenames come from a backup taken somewhere else, and storeconn addresses
// files by name and content hash, so it stores a dot-prefixed name like any
// other. Restoring one used to write the file, record a version with no files
// at all and report success — a document that every later reader, including
// ReadHashedDocument and the next backup, rejects.
//
// The check therefore lives in newVersionInfo, where a version's file set is
// established, so all three paths get it from the same place.
func TestRestoreDocumentHiddenFilesOnlyRejected(t *testing.T) {
	conn := localfsdb.NewTestConn(t)

	var (
		companyID = uu.IDFrom("6f296458-24cd-4146-ac3a-33ca885a993e")
		docID     = uu.IDFrom("c538ac93-2cf0-49a9-8378-22cd48b5ab84")
		userID    = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		v0        = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")
		data      = []byte("SECRET=1")
		hash      = docdb.ContentHash(data)
	)

	// A structurally valid backup: the version has a file, it is just not one
	// that a version directory reports as its own.
	backup := &docdb.HashedDocument{
		ID:          docID,
		CompanyID:   companyID,
		HashedFiles: map[string][]byte{hash: data},
		Versions: map[docdb.VersionTime]*docdb.HashedVersion{
			v0: {
				CommitUserID: userID,
				CommitReason: "hidden files only",
				FileHashes:   map[string]string{".env": hash},
			},
		},
	}
	require.NoError(t, backup.Validate())

	err := conn.RestoreDocument(t.Context(), backup, false)
	require.ErrorContains(t, err, "has no files")

	exists, existsErr := conn.DocumentExists(t.Context(), docID)
	require.NoError(t, existsErr)
	require.False(t, exists, "a rejected restore must leave no document behind")
}

// TestMoveDocumentBetweenCompanies covers moving a document between companies
// with a new version, which is what records the move in the document's history:
// the versions before it keep naming the previous company, and only the latest
// version decides which company the document belongs to and is listed under.
func TestMoveDocumentBetweenCompanies(t *testing.T) {
	var (
		ctx           = t.Context()
		prevCompanyID = uu.IDFrom("11111111-1111-4111-8111-111111111111")
		companyID     = uu.IDFrom("22222222-2222-4222-8222-222222222222")
		docID         = uu.IDFrom("33333333-3333-4333-8333-333333333333")
		userID        = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		v0            = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
		v1            = docdb.MustVersionTimeFromString("2024-01-02_00-00-00.000")
	)

	// A move changes nothing but the company: no file is written or removed.
	moveToCompany := func(companyID uu.ID, version docdb.VersionTime) docdb.CreateVersionFunc {
		return func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
			return &docdb.CreateVersionResult{Version: version, NewCompanyID: companyID.Nullable()}, nil
		}
	}

	// newDoc returns a store holding the document at v0 alone, owned by
	// prevCompanyID; movedDoc returns one where v1 has moved it to companyID.
	//
	// Each subtest builds its own rather than sharing one store, so every one of
	// them states the state it asserts on and runs on its own under -run. Shared
	// across the subtests these fixtures made the last one delete the version the
	// earlier ones asserted on, which made all but the first pass only as long as
	// go test happened to run them in source order.
	newDoc := func(t *testing.T) *localfsdb.Conn {
		t.Helper()
		conn := localfsdb.NewTestConn(t)
		require.NoError(t, conn.CreateDocument(
			ctx, prevCompanyID, docID, userID, "init", v0,
			newTestMemFiles("a.txt"), noopOnNew,
		))
		return conn
	}
	movedDoc := func(t *testing.T) *localfsdb.Conn {
		t.Helper()
		conn := newDoc(t)
		require.NoError(t, conn.AddDocumentVersion(
			ctx, docID, userID, "USER_DOCUMENT_MOVE", moveToCompany(companyID, v1), noopOnNew,
		))
		return conn
	}

	t.Run("a version that only changes the company is not a change-less version", func(t *testing.T) {
		conn := newDoc(t)

		err := conn.AddDocumentVersion(ctx, docID, userID, "USER_DOCUMENT_MOVE", moveToCompany(companyID, v1), noopOnNew)
		require.NoError(t, err, "a move must not be rejected as ErrNoChanges")

		versions, err := conn.DocumentVersions(ctx, docID)
		require.NoError(t, err)
		require.Equal(t, []docdb.VersionTime{v0, v1}, versions)
	})

	t.Run("the versions before the move keep the previous company", func(t *testing.T) {
		conn := movedDoc(t)

		v0Info, err := conn.DocumentVersionInfo(ctx, docID, v0)
		require.NoError(t, err)
		require.Equal(t, prevCompanyID, v0Info.CompanyID)

		v1Info, err := conn.DocumentVersionInfo(ctx, docID, v1)
		require.NoError(t, err)
		require.Equal(t, companyID, v1Info.CompanyID)
	})

	t.Run("the document belongs to and is listed under the company of its latest version", func(t *testing.T) {
		conn := movedDoc(t)

		docCompanyID, err := conn.DocumentCompanyID(ctx, docID)
		require.NoError(t, err)
		require.Equal(t, companyID, docCompanyID)

		docIDs, err := conn.CompanyDocumentIDs(ctx, companyID)
		require.NoError(t, err)
		require.Equal(t, uu.IDSlice{docID}, docIDs)

		// The company the document was moved away from must not list it any
		// more, even though the version before the move still names it.
		docIDs, err = conn.CompanyDocumentIDs(ctx, prevCompanyID)
		require.NoError(t, err)
		require.Nil(t, docIDs)
	})

	t.Run("deleting the move re-assigns the document to the previous company", func(t *testing.T) {
		conn := movedDoc(t)

		leftVersions, err := conn.DeleteDocumentVersion(ctx, docID, v1)
		require.NoError(t, err)
		require.Equal(t, []docdb.VersionTime{v0}, leftVersions)

		docCompanyID, err := conn.DocumentCompanyID(ctx, docID)
		require.NoError(t, err)
		require.Equal(t, prevCompanyID, docCompanyID, "the document must follow the company of its new latest version")

		docIDs, err := conn.CompanyDocumentIDs(ctx, prevCompanyID)
		require.NoError(t, err)
		require.Equal(t, uu.IDSlice{docID}, docIDs)

		docIDs, err = conn.CompanyDocumentIDs(ctx, companyID)
		require.NoError(t, err)
		require.Nil(t, docIDs, "the document must no longer be listed under the company of the deleted version")
	})
}

// TestSetDocumentCompanyIDSurvives covers the operations that re-derive a
// document's company from its latest version. Each of them must do so only when
// it actually changed which version is the latest one: SetDocumentCompanyID
// moves the company marker without committing a version, so the marker names a
// company that no version of the document names, on purpose. An operation that
// re-derives unconditionally silently undoes that move.
func TestSetDocumentCompanyIDSurvives(t *testing.T) {
	var (
		ctx      = t.Context()
		companyA = uu.IDFrom("11111111-1111-4111-8111-111111111111")
		companyB = uu.IDFrom("22222222-2222-4222-8222-222222222222")
		docID    = uu.IDFrom("33333333-3333-4333-8333-333333333333")
		userID   = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		v0       = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
		v1       = docdb.MustVersionTimeFromString("2024-01-02_00-00-00.000")
	)

	// movedDoc returns a document owned by companyB through the marker alone:
	// every version of it still names companyA.
	movedDoc := func(t *testing.T) *localfsdb.Conn {
		t.Helper()
		conn := localfsdb.NewTestConn(t)
		require.NoError(t, conn.CreateDocument(
			ctx, companyA, docID, userID, "v0", v0,
			newTestMemFiles("a.txt"), noopOnNew,
		))
		require.NoError(t, conn.AddDocumentVersion(
			ctx, docID, userID, "v1",
			func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
				return &docdb.CreateVersionResult{Version: v1, WriteFiles: newTestMemFiles("b.txt")}, nil
			},
			noopOnNew,
		))
		require.NoError(t, conn.SetDocumentCompanyID(ctx, docID, companyB))
		return conn
	}

	requireOwnedBy := func(t *testing.T, conn *localfsdb.Conn, companyID uu.ID, msgAndArgs ...any) {
		t.Helper()
		docCompanyID, err := conn.DocumentCompanyID(ctx, docID)
		require.NoError(t, err)
		require.Equal(t, companyID, docCompanyID, msgAndArgs...)
		docIDs, err := conn.CompanyDocumentIDs(ctx, companyID)
		require.NoError(t, err)
		require.Equal(t, uu.IDSlice{docID}, docIDs, msgAndArgs...)
	}

	t.Run("deleting a version that is not the latest keeps the moved company", func(t *testing.T) {
		conn := movedDoc(t)

		// v0 is the oldest version and cannot decide who owns the document, so
		// deleting it must not touch the company marker.
		leftVersions, err := conn.DeleteDocumentVersion(ctx, docID, v0)
		require.NoError(t, err)
		require.Equal(t, []docdb.VersionTime{v1}, leftVersions)

		requireOwnedBy(t, conn, companyB, "deleting an older version must not undo SetDocumentCompanyID")
	})

	t.Run("deleting the latest version re-derives the company from the new latest one", func(t *testing.T) {
		conn := movedDoc(t)

		// The counterpart: v1 is the latest version, so deleting it does change
		// which version the document's company has to come from.
		leftVersions, err := conn.DeleteDocumentVersion(ctx, docID, v1)
		require.NoError(t, err)
		require.Equal(t, []docdb.VersionTime{v0}, leftVersions)

		requireOwnedBy(t, conn, companyA, "the document must follow the company of its new latest version")
	})

	t.Run("a merge restore that writes nothing keeps the moved company", func(t *testing.T) {
		conn := movedDoc(t)
		backup, err := docdb.ReadHashedDocument(ctx, conn, docID)
		require.NoError(t, err)
		require.Equal(t, companyB, backup.CompanyID)

		// Re-syncing the document into itself: every version is already there,
		// so this restore has nothing to write and must change nothing.
		require.NoError(t, conn.RestoreDocument(ctx, backup, false))

		requireOwnedBy(t, conn, companyB, "an incremental sync must not undo SetDocumentCompanyID")
	})

	t.Run("a merge restore that writes a new latest version takes its company", func(t *testing.T) {
		conn := movedDoc(t)
		backup, err := docdb.ReadHashedDocument(ctx, conn, docID)
		require.NoError(t, err)

		// The counterpart: a restore into a destination missing the latest
		// version does establish who owns the document.
		target := localfsdb.NewTestConn(t)
		require.NoError(t, target.CreateDocument(
			ctx, companyA, docID, userID, "v0", v0,
			newTestMemFiles("a.txt"), noopOnNew,
		))
		require.NoError(t, target.RestoreDocument(ctx, backup, false))

		requireOwnedBy(t, target, companyB, "the restored latest version decides the company")
	})
}

// TestRestoreDocumentRelinksSuccessor covers a merge restore that fills a
// version back into the middle of an existing chain: the successor was relinked
// to the deleted version's own predecessor when it was deleted, and the restore
// has to take that back. Otherwise the successor keeps naming a predecessor
// that is no longer the version before it and the chain forks.
func TestRestoreDocumentRelinksSuccessor(t *testing.T) {
	var (
		ctx       = t.Context()
		companyID = uu.IDFrom("3a4f1c2e-7b8d-4e9a-b1c2-d3e4f5a6b7c8")
		docID     = uu.IDFrom("11111111-2222-4333-8444-555555555555")
		userID    = uu.IDFrom("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
		v0        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
		v1        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.001")
		v2        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.002")
	)

	conn := localfsdb.NewTestConn(t)
	require.NoError(t, conn.CreateDocument(
		ctx, companyID, docID, userID, "v0", v0,
		newTestMemFiles("a.txt"), noopOnNew,
	))
	require.NoError(t, conn.AddDocumentVersion(
		ctx, docID, userID, "v1",
		func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
			return &docdb.CreateVersionResult{Version: v1, WriteFiles: newTestMemFiles("b.txt")}, nil
		},
		noopOnNew,
	))
	require.NoError(t, conn.AddDocumentVersion(
		ctx, docID, userID, "v2",
		func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
			return &docdb.CreateVersionResult{Version: v2, WriteFiles: newTestMemFiles("c.txt")}, nil
		},
		noopOnNew,
	))

	backup, err := docdb.ReadHashedDocument(ctx, conn, docID)
	require.NoError(t, err)

	// A destination that has v0 and v2 but not v1, with v2 chained off v0
	// because that is the version it was restored after. Built by restoring a
	// backup with the middle version taken out, which is what a destination
	// looks like after v1 was deleted from it and it was re-synced.
	partial := &docdb.HashedDocument{
		ID:          backup.ID,
		CompanyID:   backup.CompanyID,
		HashedFiles: backup.HashedFiles,
		Versions:    maps.Clone(backup.Versions),
	}
	delete(partial.Versions, v1)

	target := localfsdb.NewTestConn(t)
	require.NoError(t, target.RestoreDocument(ctx, partial, false))
	v2Info, err := target.DocumentVersionInfo(ctx, docID, v2)
	require.NoError(t, err)
	require.Equal(t, &v0, v2Info.PrevVersion, "without v1 the destination chains v2 off v0")

	// Restoring the full backup fills v1 back in between them. Leaving v2
	// chained off v0 would fork the chain: two versions naming the same
	// predecessor, and v2 naming one that is no longer the version before it.
	require.NoError(t, target.RestoreDocument(ctx, backup, false))

	versions, err := target.DocumentVersions(ctx, docID)
	require.NoError(t, err)
	require.Equal(t, []docdb.VersionTime{v0, v1, v2}, versions)

	v1Info, err := target.DocumentVersionInfo(ctx, docID, v1)
	require.NoError(t, err)
	require.Equal(t, &v0, v1Info.PrevVersion)

	v2Info, err = target.DocumentVersionInfo(ctx, docID, v2)
	require.NoError(t, err)
	require.Equal(t, &v1, v2Info.PrevVersion, "the restored v1 must take v2 back as its successor")
}

// newTestDocVersions creates docID with the passed versions on a fresh conn —
// a genesis version plus one file-adding version each — and returns the conn
// together with a backup of the document. The versions are the chain a
// destination is expected to end up with after the missing ones are restored
// into it.
func newTestDocVersions(t *testing.T, companyID, docID, userID uu.ID, versions ...docdb.VersionTime) (*localfsdb.Conn, *docdb.HashedDocument) {
	t.Helper()
	ctx := t.Context()
	conn := localfsdb.NewTestConn(t)
	require.NoError(t, conn.CreateDocument(
		ctx, companyID, docID, userID, "v0", versions[0],
		newTestMemFiles("f0.txt"), noopOnNew,
	))
	for i, version := range versions[1:] {
		filename := fmt.Sprintf("f%d.txt", i+1)
		require.NoError(t, conn.AddDocumentVersion(
			ctx, docID, userID, filename,
			func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
				return &docdb.CreateVersionResult{Version: version, WriteFiles: newTestMemFiles(filename)}, nil
			},
			noopOnNew,
		))
	}
	backup, err := docdb.ReadHashedDocument(ctx, conn, docID)
	require.NoError(t, err)
	return conn, backup
}

// withoutVersions returns a copy of doc with the passed versions taken out,
// which is the backup a destination that lost them was last synced from.
func withoutVersions(doc *docdb.HashedDocument, versions ...docdb.VersionTime) *docdb.HashedDocument {
	partial := &docdb.HashedDocument{
		ID:          doc.ID,
		CompanyID:   doc.CompanyID,
		HashedFiles: doc.HashedFiles,
		Versions:    maps.Clone(doc.Versions),
	}
	for _, version := range versions {
		delete(partial.Versions, version)
	}
	return partial
}

// TestDeleteDocumentVersionRelinksSuccessor asserts that deleting a version
// hands its successor over to the version before it, so no version is left
// naming a predecessor the document no longer has.
//
// pgstore relinks in the same call, and RestoreDocument on both implementations
// undoes exactly this relink when the deleted version is restored (see
// storeconn.CreateDocumentVersionInput.RelinkSuccessor). Leaving the successor
// on the removed version instead made the two implementations answer
// differently for the same delete, and left a chain a caller cannot walk
// backwards: DocumentVersions no longer lists the predecessor it names.
func TestDeleteDocumentVersionRelinksSuccessor(t *testing.T) {
	var (
		ctx       = t.Context()
		companyID = uu.IDFrom("3a4f1c2e-7b8d-4e9a-b1c2-d3e4f5a6b7c8")
		docID     = uu.IDFrom("11111111-2222-4333-8444-555555555555")
		userID    = uu.IDFrom("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
		v0        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
		v1        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.001")
		v2        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.002")
		v3        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.003")
	)

	prevVersionOf := func(t *testing.T, conn *localfsdb.Conn, version docdb.VersionTime) *docdb.VersionTime {
		t.Helper()
		info, err := conn.DocumentVersionInfo(ctx, docID, version)
		require.NoError(t, err)
		return info.PrevVersion
	}

	t.Run("middle version", func(t *testing.T) {
		conn, _ := newTestDocVersions(t, companyID, docID, userID, v0, v1, v2, v3)

		left, err := conn.DeleteDocumentVersion(ctx, docID, v1)
		require.NoError(t, err)
		require.Equal(t, []docdb.VersionTime{v0, v2, v3}, left)
		require.Equal(t, &v0, prevVersionOf(t, conn, v2), "v2 must take over v1's predecessor")
		require.Equal(t, &v2, prevVersionOf(t, conn, v3), "v3 never named v1 and must be left alone")

		// Deleting the version that just took the successor over hands it on
		// again, so a run of deletes leaves the remaining versions chained.
		_, err = conn.DeleteDocumentVersion(ctx, docID, v2)
		require.NoError(t, err)
		require.Equal(t, &v0, prevVersionOf(t, conn, v3))
	})

	t.Run("genesis version keeps its successor", func(t *testing.T) {
		conn, backup := newTestDocVersions(t, companyID, docID, userID, v0, v1, v2)

		// A deleted genesis version has no predecessor to hand the successor
		// to, and pgstore deliberately leaves the successor naming it rather
		// than making it a genesis of its own.
		_, err := conn.DeleteDocumentVersion(ctx, docID, v0)
		require.NoError(t, err)
		require.Equal(t, &v0, prevVersionOf(t, conn, v1), "the successor of a deleted genesis version keeps naming it")

		// Which is what lets the merge-restore take the earliest version back:
		// it is written as the genesis it was, and v1 chains off it again
		// instead of the document holding two versions without a predecessor.
		require.NoError(t, conn.RestoreDocument(ctx, backup, false))
		require.Nil(t, prevVersionOf(t, conn, v0))
		require.Equal(t, &v0, prevVersionOf(t, conn, v1))
		require.Equal(t, &v1, prevVersionOf(t, conn, v2))
	})
}

// TestRestoreDocumentRelinksSuccessorAcrossAdjacentMissingVersions covers a
// destination missing a run of consecutive versions, which is what deleting
// them one after another leaves behind: every DeleteDocumentVersion relinks the
// deleted version's successor onto its predecessor, so the version after the
// run ends up chained off the version before it.
//
// Filling the run back in has to hand that successor from one restored version
// to the next. Relinking only the version that follows in the backup names one
// the destination does not have yet, which relinks nothing and leaves the
// successor on the version before the run: two versions naming the same
// predecessor — the fork storeconn's one-successor-per-version index refuses
// and HashedDocument.Validate rejects at the next backup of this document.
func TestRestoreDocumentRelinksSuccessorAcrossAdjacentMissingVersions(t *testing.T) {
	var (
		ctx       = t.Context()
		companyID = uu.IDFrom("3a4f1c2e-7b8d-4e9a-b1c2-d3e4f5a6b7c8")
		docID     = uu.IDFrom("11111111-2222-4333-8444-555555555555")
		userID    = uu.IDFrom("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
		v0        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
		v1        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.001")
		v2        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.002")
		v3        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.003")
	)

	_, backup := newTestDocVersions(t, companyID, docID, userID, v0, v1, v2, v3)

	// A destination that lost v1 and v2, with v3 chained off v0 the way two
	// deletes leave it.
	target := localfsdb.NewTestConn(t)
	require.NoError(t, target.RestoreDocument(ctx, withoutVersions(backup, v1, v2), false))
	v3Info, err := target.DocumentVersionInfo(ctx, docID, v3)
	require.NoError(t, err)
	require.Equal(t, &v0, v3Info.PrevVersion, "without v1 and v2 the destination chains v3 off v0")

	require.NoError(t, target.RestoreDocument(ctx, backup, false))

	versions, err := target.DocumentVersions(ctx, docID)
	require.NoError(t, err)
	require.Equal(t, []docdb.VersionTime{v0, v1, v2, v3}, versions)

	// v3 is taken over twice: v1 takes it back from v0 when it is filled in,
	// and v2 takes it from v1 in turn, which ends the chain at v0→v1→v2→v3
	// instead of forking it.
	v1Info, err := target.DocumentVersionInfo(ctx, docID, v1)
	require.NoError(t, err)
	require.Equal(t, &v0, v1Info.PrevVersion)

	v2Info, err := target.DocumentVersionInfo(ctx, docID, v2)
	require.NoError(t, err)
	require.Equal(t, &v1, v2Info.PrevVersion)

	v3Info, err = target.DocumentVersionInfo(ctx, docID, v3)
	require.NoError(t, err)
	require.Equal(t, &v2, v3Info.PrevVersion, "the last restored version of the run must end up with the successor")

	// The restored document is backupable again, which a forked chain is not.
	restored, err := docdb.ReadHashedDocument(ctx, target, docID)
	require.NoError(t, err)
	require.NoError(t, restored.Validate())
}

// TestRestoreDocumentRollbackRestoresRelinkedSuccessor asserts that a failed
// restore puts a relinked successor back the way it was before the call, not
// the way an earlier version of the same call left it.
//
// The successor of a run of restored versions is rewritten once per version of
// the run, so only the content from before the first rewrite undoes all of
// them. Saving it again on every rewrite would restore what this call wrote.
func TestRestoreDocumentRollbackRestoresRelinkedSuccessor(t *testing.T) {
	var (
		ctx       = t.Context()
		companyID = uu.IDFrom("3a4f1c2e-7b8d-4e9a-b1c2-d3e4f5a6b7c8")
		docID     = uu.IDFrom("11111111-2222-4333-8444-555555555555")
		userID    = uu.IDFrom("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
		v0        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
		v1        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.001")
		v2        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.002")
		v3        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.003")
		v4        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.004")
	)

	_, backup := newTestDocVersions(t, companyID, docID, userID, v0, v1, v2, v3, v4)

	target, documentsDir, _ := newTestConnDirs(t)
	require.NoError(t, target.RestoreDocument(ctx, withoutVersions(backup, v1, v2, v3), false))

	// A regular file where v3's version directory has to be created, so the
	// restore fails after v1 and v2 were written and both relinked v4.
	docDir := uuiddir.Join(documentsDir, docID)
	require.NoError(t, docDir.Join(v3.String()).WriteAll([]byte("not a version directory")))

	require.Error(t, target.RestoreDocument(ctx, backup, false))

	versions, err := target.DocumentVersions(ctx, docID)
	require.NoError(t, err)
	require.Equal(t, []docdb.VersionTime{v0, v4}, versions, "the rollback must remove every version this call wrote")

	v4Info, err := target.DocumentVersionInfo(ctx, docID, v4)
	require.NoError(t, err)
	require.Equal(t, &v0, v4Info.PrevVersion, "the rollback must chain v4 off v0 again, not off a version it removed")
}

// TestSyncDocumentMovedBackToPreviousCompany covers a document whose latest
// version is a company move that was later undone with SetDocumentCompanyID.
//
// Reading it back collapses that version into its predecessor: the move version
// changed nothing but the company, and the marker move renamed it to the
// company the predecessor already names, so the two versions become
// indistinguishable. That is a state the public API produces, and the document
// has to stay backupable and syncable in it — rejecting the backup would not
// undo the collapse, only make the document impossible to copy for good.
func TestSyncDocumentMovedBackToPreviousCompany(t *testing.T) {
	var (
		ctx      = t.Context()
		companyA = uu.IDFrom("11111111-1111-4111-8111-111111111111")
		companyB = uu.IDFrom("22222222-2222-4222-8222-222222222222")
		docID    = uu.IDFrom("33333333-3333-4333-8333-333333333333")
		userID   = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		v0       = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
		v1       = docdb.MustVersionTimeFromString("2024-01-02_00-00-00.000")
	)

	src := localfsdb.NewTestConn(t)
	require.NoError(t, src.CreateDocument(
		ctx, companyA, docID, userID, "v0", v0,
		newTestMemFiles("a.txt"), noopOnNew,
	))
	// A pure company move: no file is written or removed.
	require.NoError(t, src.AddDocumentVersion(
		ctx, docID, userID, "USER_DOCUMENT_MOVE",
		func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
			return &docdb.CreateVersionResult{Version: v1, NewCompanyID: companyB.Nullable()}, nil
		},
		noopOnNew,
	))
	// Moved back, marker only. v1 now names the company v0 already names.
	require.NoError(t, src.SetDocumentCompanyID(ctx, docID, companyA))

	backup, err := docdb.ReadHashedDocument(ctx, src, docID)
	require.NoError(t, err)
	require.NoError(t, backup.Validate(),
		"a document the public API can produce must be backupable")
	require.Equal(t, companyA, backup.CompanyID)

	dest := localfsdb.NewTestConn(t)
	require.NoError(t, docdb.SyncDocument(ctx, src, dest, docID, false))

	destCompanyID, err := dest.DocumentCompanyID(ctx, docID)
	require.NoError(t, err)
	require.Equal(t, companyA, destCompanyID)

	versions, err := dest.DocumentVersions(ctx, docID)
	require.NoError(t, err)
	require.Equal(t, []docdb.VersionTime{v0, v1}, versions,
		"both versions must survive the copy, collapsed or not")
}

// TestDeleteDocumentVersionWithUnreadableInfoFile asserts that a version whose
// info JSON cannot be read is still deleted.
//
// A crash between writing a version's directory and writing its info file
// leaves exactly this state, and DeleteDocumentVersion is what cleans it up.
// Refusing the delete because the file cannot be parsed made those versions the
// ones that could not be removed: the only way out was deleting the file by
// hand, and until then every read of the document reported it. The successor is
// left naming the deleted version, because the predecessor to hand it to was
// only recorded in the file that is unreadable — the same state a deleted
// genesis version leaves behind, and one a merge-restore undoes.
func TestDeleteDocumentVersionWithUnreadableInfoFile(t *testing.T) {
	var (
		ctx       = t.Context()
		companyID = uu.IDFrom("3a4f1c2e-7b8d-4e9a-b1c2-d3e4f5a6b7c8")
		docID     = uu.IDFrom("11111111-2222-4333-8444-555555555555")
		userID    = uu.IDFrom("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
		v0        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
		v1        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.001")
		v2        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.002")
	)

	conn, documentsDir, _ := newTestConnDirs(t)
	require.NoError(t, conn.CreateDocument(
		ctx, companyID, docID, userID, "v0", v0,
		newTestMemFiles("f0.txt"), noopOnNew,
	))
	for _, version := range []docdb.VersionTime{v1, v2} {
		filename := "f" + version.String() + ".txt"
		require.NoError(t, conn.AddDocumentVersion(
			ctx, docID, userID, "add "+filename,
			func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
				return &docdb.CreateVersionResult{Version: version, WriteFiles: newTestMemFiles(filename)}, nil
			},
			noopOnNew,
		))
	}

	// Truncated the way an interrupted write leaves it: the file is there, so
	// the version is not simply treated as info-less, but it does not parse.
	docDir := uuiddir.Join(documentsDir, docID)
	infoFile := docDir.Joinf("%s.json", v1)
	require.True(t, infoFile.Exists(), "the version info file must exist for this test to mean anything")
	require.NoError(t, infoFile.WriteAll([]byte(`{"DocID":"`)))

	left, err := conn.DeleteDocumentVersion(ctx, docID, v1)
	require.NoError(t, err, "a version with an unreadable info file must still be deletable")
	require.Equal(t, []docdb.VersionTime{v0, v2}, left)
	require.False(t, infoFile.Exists(), "the unreadable info file must be removed with its version")

	_, err = conn.DocumentVersionInfo(ctx, docID, v1)
	require.Error(t, err, "the deleted version must be gone")

	// The predecessor was lost with the file, so v2 keeps naming v1 rather than
	// being chained onto v0 — stated here so the limitation is pinned rather
	// than discovered.
	v2Info, err := conn.DocumentVersionInfo(ctx, docID, v2)
	require.NoError(t, err)
	require.Equal(t, &v1, v2Info.PrevVersion,
		"without a readable info file there is no predecessor to relink the successor onto")
}

// documentDirCall is one Conn entry point that resolves a document directory
// before doing anything else, named after the method under test.
type documentDirCall struct {
	name string
	call func(conn *localfsdb.Conn, docID uu.ID) error
}

// documentDirCalls returns one call per guard that turns a missing document
// directory into docdb.ErrDocumentNotFound. Conn.DocumentExists resolves the
// same directory but answers with a bool rather than that error, so it is
// asserted separately by each test using this table.
func documentDirCalls(ctx context.Context, version docdb.VersionTime) []documentDirCall {
	return []documentDirCall{
		{"DocumentVersions", func(conn *localfsdb.Conn, docID uu.ID) error {
			_, err := conn.DocumentVersions(ctx, docID)
			return err
		}},
		{"LatestDocumentVersionInfo", func(conn *localfsdb.Conn, docID uu.ID) error {
			_, err := conn.LatestDocumentVersionInfo(ctx, docID)
			return err
		}},
		{"DocumentVersionInfo", func(conn *localfsdb.Conn, docID uu.ID) error {
			_, err := conn.DocumentVersionInfo(ctx, docID, version)
			return err
		}},
		{"ReadDocumentVersionFile", func(conn *localfsdb.Conn, docID uu.ID) error {
			_, err := conn.ReadDocumentVersionFile(ctx, docID, version, "f0.txt")
			return err
		}},
	}
}

// requirePermissionBitsEnforced skips a test that makes a directory unreadable
// where doing so has no effect, so the test cannot pass for the wrong reason by
// never producing the failure it asserts on.
func requirePermissionBitsEnforced(t *testing.T) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("skipping because directory permission bits are not enforced on windows")
	}
	if os.Geteuid() == 0 {
		t.Skip("skipping because running as root bypasses directory permission bits")
	}
}

// restoreDirPermissions makes dir usable again after a test made it
// unreadable, so the temp dir it lives in can still be removed.
func restoreDirPermissions(t *testing.T, dir fs.File) {
	t.Helper()
	if err := os.Chmod(dir.LocalPath(), 0o700); err != nil {
		t.Errorf("can't restore permissions of %s because of: %s", dir.LocalPath(), err)
	}
}

// TestDocumentNotFoundForAbsentDocument is the regression guard for the
// existing contract: a document that was never stored is still reported as
// docdb.ErrDocumentNotFound, and DocumentExists still answers (false, nil)
// for it.
func TestDocumentNotFoundForAbsentDocument(t *testing.T) {
	var (
		ctx      = t.Context()
		absentID = uu.IDFrom("dddddddd-eeee-4fff-8aaa-bbbbbbbbbbbb")
		v0       = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
		conn     = localfsdb.NewTestConn(t)
	)

	for _, c := range documentDirCalls(ctx, v0) {
		t.Run(c.name, func(t *testing.T) {
			err := c.call(conn, absentID)
			require.ErrorIs(t, err, docdb.NewErrDocumentNotFound(absentID))
		})
	}

	t.Run("DocumentExists", func(t *testing.T) {
		exists, err := conn.DocumentExists(ctx, absentID)
		require.NoError(t, err, "a document that is genuinely absent is not an error")
		require.False(t, exists)
	})
}

// TestUnreadableDocumentDirIsNotDocumentNotFound pins the distinction the
// ErrDocumentNotFound contract rests on. Callers treat it as "nothing here,
// carry on" — one of them rebuilds a document's version chain from a source its
// own documentation calls non-authoritative — so a document store that merely
// could not be read must never produce it. A directory whose stat failed is not
// a directory known to be absent.
func TestUnreadableDocumentDirIsNotDocumentNotFound(t *testing.T) {
	requirePermissionBitsEnforced(t)

	var (
		ctx       = t.Context()
		companyID = uu.IDFrom("3a4f1c2e-7b8d-4e9a-b1c2-d3e4f5a6b7c8")
		docID     = uu.IDFrom("11111111-2222-4333-8444-555555555555")
		userID    = uu.IDFrom("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
		v0        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
	)

	conn, documentsDir, _ := newTestConnDirs(t)
	require.NoError(t, conn.CreateDocument(
		ctx, companyID, docID, userID, "v0", v0,
		newTestMemFiles("f0.txt"), noopOnNew,
	))

	// The document itself is intact on disk; only the directory above it is
	// made unreadable, the way an unmounted volume or a changed permission
	// makes a present document impossible to look at.
	parentDir := uuiddir.Join(documentsDir, docID).Dir()
	t.Cleanup(func() { restoreDirPermissions(t, parentDir) })
	require.NoError(t, os.Chmod(parentDir.LocalPath(), 0o000))

	for _, c := range documentDirCalls(ctx, v0) {
		t.Run(c.name, func(t *testing.T) {
			err := c.call(conn, docID)
			require.ErrorIs(t, err, os.ErrPermission,
				"the directory that could not be read must surface as the permission error it is")
			require.False(t, errs.Has[docdb.ErrDocumentNotFound](err),
				"a document that could not be looked at must not be reported as absent: %v", err)
			require.NotErrorIs(t, err, os.ErrNotExist,
				"callers swallow os.ErrNotExist as 'nothing here', which an unreadable store is not: %v", err)
		})
	}

	t.Run("DocumentExists", func(t *testing.T) {
		exists, err := conn.DocumentExists(ctx, docID)
		require.Error(t, err, "DocumentExists must not answer a clean (false, nil) for a store it cannot read")
		require.ErrorIs(t, err, os.ErrPermission)
		require.False(t, exists)
	})
}

// TestUnreadableVersionDirIsNotVersionNotFound is the same distinction one
// level down: an unreadable version directory is not a version that does not
// exist.
func TestUnreadableVersionDirIsNotVersionNotFound(t *testing.T) {
	requirePermissionBitsEnforced(t)

	var (
		ctx       = t.Context()
		companyID = uu.IDFrom("3a4f1c2e-7b8d-4e9a-b1c2-d3e4f5a6b7c8")
		docID     = uu.IDFrom("11111111-2222-4333-8444-555555555555")
		userID    = uu.IDFrom("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
		v0        = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
	)

	conn, documentsDir, _ := newTestConnDirs(t)
	require.NoError(t, conn.CreateDocument(
		ctx, companyID, docID, userID, "v0", v0,
		newTestMemFiles("f0.txt"), noopOnNew,
	))

	// Readable but not traversable: the document directory can still be stat'ed
	// as a directory, so the lookup that fails is the one for the version
	// inside it rather than the one for the document.
	docDir := uuiddir.Join(documentsDir, docID)
	t.Cleanup(func() { restoreDirPermissions(t, docDir) })
	require.NoError(t, os.Chmod(docDir.LocalPath(), 0o600))

	_, err := conn.ReadDocumentVersionFile(ctx, docID, v0, "f0.txt")
	require.ErrorIs(t, err, os.ErrPermission)
	require.False(t, errs.Has[docdb.ErrDocumentVersionNotFound](err),
		"a version directory that could not be looked at must not be reported as absent: %v", err)
}
