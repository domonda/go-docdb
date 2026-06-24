package localfsdb_test

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sync"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/localfsdb"
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
	noopOnNew := func(context.Context, *docdb.VersionInfo) error { return nil }

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
		noopOnNew   = func(context.Context, *docdb.VersionInfo) error { return nil }
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
	tmp := fs.File(t.TempDir())
	documentsDir := tmp.Join("documents")
	companiesDir := tmp.Join("companies")
	require.NoError(t, documentsDir.MakeDir())
	require.NoError(t, companiesDir.MakeDir())

	conn := localfsdb.NewConn(documentsDir, companiesDir)

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
