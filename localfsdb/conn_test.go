package localfsdb_test

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/localfsdb"
	"github.com/domonda/go-types/uu"
)

func TestCreateDocument(t *testing.T) {
	conns := []docdb.Conn{
		localfsdb.NewTestConn(t),
	}
	for _, conn := range conns {
		testCreateDocument(t, conn)
	}
}

func testCreateDocument(t *testing.T, conn docdb.Conn) {
	var (
		versionTime0     = docdb.MustVersionTimeFromString("2023-01-01_00-00-00.000")
		defaultCtx       = docdb.ContextWithVersionTime(context.Background(), versionTime0)
		defaultCompanyID = uu.IDFrom("2fc110fd-ed66-4a8f-9498-4dcb8386d300")
		defaultUserID    = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		defaultReason    = "TestCreateDocument"
	)
	type args struct {
		ctx       context.Context
		companyID uu.ID
		docID     uu.ID
		userID    uu.ID
		reason    string
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
			args:         args{ctx: context.Background()},
			wantFinalErr: true,
		},
		{
			name: "create document without files",
			args: args{
				ctx:       defaultCtx,
				companyID: defaultCompanyID,
				docID:     uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171"),
				userID:    defaultUserID,
				reason:    defaultReason,
				files:     nil,
			},
			wantVersionInfo: &docdb.VersionInfo{
				CompanyID:    defaultCompanyID,
				DocID:        uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171"),
				Version:      versionTime0,
				CommitUserID: defaultUserID,
				CommitReason: defaultReason,
				Files:        newTestFileInfos(),
			},
			wantFiles: newTestMemFiles(),
		},
		{
			name: "create document with 1 file",
			args: args{
				ctx:       defaultCtx,
				companyID: defaultCompanyID,
				docID:     uu.IDFrom("a3bf09b6-d2e4-400d-bdf1-fa0a63f934d1"),
				userID:    defaultUserID,
				reason:    defaultReason,
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
				ctx:       defaultCtx,
				companyID: defaultCompanyID,
				docID:     uu.IDFrom("ba4260f6-18c7-4213-8afc-7d041ed7df8d"),
				userID:    defaultUserID,
				reason:    defaultReason,
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
			gotVersionInfo, err := conn.CreateDocument(
				tt.args.ctx,
				tt.args.companyID,
				tt.args.docID,
				tt.args.userID,
				tt.args.reason,
				tt.args.files,
			)
			require.True(t, gotVersionInfo != nil && err == nil || gotVersionInfo == nil && err != nil)
			require.Equal(t, tt.wantVersionInfo, gotVersionInfo)
			if gotVersionInfo != nil {
				require.NoError(t, docdb.CheckConnDocumentVersionFiles(defaultCtx, conn, tt.args.docID, gotVersionInfo.Version, tt.wantFiles))
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
			gotCompanyID, err := conn.DocumentCompanyID(defaultCtx, tt.args.docID)
			require.NoError(t, err)
			require.Equal(t, defaultCompanyID, gotCompanyID)
		})
	}
}

func TestAddDocumentVersion(t *testing.T) {
	conns := []docdb.Conn{
		localfsdb.NewTestConn(t),
	}
	for _, conn := range conns {
		testAddDocumentVersion(t, conn)
	}
}

func testAddDocumentVersion(t *testing.T, conn docdb.Conn) {
	var (
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
		ctx                   context.Context
		docID                 uu.ID
		userID                uu.ID
		reason                string
		createVersion         docdb.CreateVersionFunc
		onNewVersionResultErr error
	}
	type call struct {
		args            args
		wantVersionInfo *docdb.VersionInfo
		wantFiles       []fs.FileReader
	}
	tests := []struct {
		name            string
		createCtx       context.Context
		createCompanyID uu.ID
		createDocID     uu.ID
		createUserID    uu.ID
		createReason    string
		createFiles     []fs.FileReader
		calls           []call
		wantFinalErr    bool
		wantFinalErrIs  error
		wantFinalErrAs  error
	}{
		{
			name:            "invalid call",
			createCtx:       docdb.ContextWithVersionTime(context.Background(), versionTime0),
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("a920f1ab-f150-4455-96ec-af3747f0fa78"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createFiles:     newTestMemFiles("a.txt"),
			calls:           []call{{args: args{ctx: context.Background()}}},
			wantFinalErr:    true,
		},
		{
			name:            "createVersion returns error",
			createCtx:       docdb.ContextWithVersionTime(context.Background(), versionTime0),
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("142f465b-bc8b-4285-aed8-21917c924e47"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createFiles:     newTestMemFiles("a.txt"),
			calls: []call{
				{
					args: args{
						ctx:    docdb.ContextWithVersionTime(context.Background(), versionTime1),
						docID:  uu.IDFrom("142f465b-bc8b-4285-aed8-21917c924e47"),
						userID: defaultUserID,
						reason: "second version",
						createVersion: func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error) {
							return nil, nil, nil, testError1
						},
						onNewVersionResultErr: nil,
					},
				},
			},
			wantFinalErrIs: testError1,
		},
		{
			name:            "no changes",
			createCtx:       docdb.ContextWithVersionTime(context.Background(), versionTime0),
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("cae28b7d-1b76-4fe3-b362-758f88396239"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createFiles:     newTestMemFiles("a.txt"),
			calls: []call{
				{
					args: args{
						ctx:    docdb.ContextWithVersionTime(context.Background(), versionTime1),
						docID:  uu.IDFrom("cae28b7d-1b76-4fe3-b362-758f88396239"),
						userID: defaultUserID,
						reason: "second version",
						createVersion: func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error) {
							return nil, nil, nil, nil
						},
						onNewVersionResultErr: nil,
					},
				},
			},
			wantFinalErrIs: docdb.ErrNoChanges,
		},
		{
			name:            "write identical file",
			createCtx:       docdb.ContextWithVersionTime(context.Background(), versionTime0),
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("21dc078a-b930-42ae-b4f6-6b8bea86050e"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createFiles:     newTestMemFiles("a.txt"),
			calls: []call{
				{
					args: args{
						ctx:    docdb.ContextWithVersionTime(context.Background(), versionTime1),
						docID:  uu.IDFrom("21dc078a-b930-42ae-b4f6-6b8bea86050e"),
						userID: defaultUserID,
						reason: "second version",
						createVersion: func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error) {
							return newTestMemFiles("a.txt"), nil, nil, nil
						},
						onNewVersionResultErr: nil,
					},
					wantVersionInfo: nil,
					wantFiles:       nil,
				},
			},
			wantFinalErrIs: docdb.ErrNoChanges,
		},
		{
			name:            "change 1 file",
			createCtx:       docdb.ContextWithVersionTime(context.Background(), versionTime0),
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createFiles:     newTestMemFiles("a.txt"),
			calls: []call{
				{
					args: args{
						ctx:    docdb.ContextWithVersionTime(context.Background(), versionTime1),
						docID:  uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						userID: defaultUserID,
						reason: "second version",
						createVersion: func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error) {
							return []fs.FileReader{fs.NewMemFile("a.txt", []byte("CHANGED"))}, nil, nil, nil
						},
						onNewVersionResultErr: nil,
					},
					wantVersionInfo: &docdb.VersionInfo{
						CompanyID:     defaultCompanyID,
						DocID:         uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						Version:       versionTime1,
						PrevVersion:   versionTime0,
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
						ctx:    docdb.ContextWithVersionTime(context.Background(), versionTime2),
						docID:  uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						userID: defaultUserID,
						reason: "third version",
						createVersion: func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error) {
							return []fs.FileReader{fs.NewMemFile("a.txt", []byte("CHANGED AGAIN"))}, nil, nil, nil
						},
						onNewVersionResultErr: nil,
					},
					wantVersionInfo: &docdb.VersionInfo{
						CompanyID:     defaultCompanyID,
						DocID:         uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						Version:       versionTime2,
						PrevVersion:   versionTime1,
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
						ctx:    docdb.ContextWithVersionTime(context.Background(), versionTime3),
						docID:  uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						userID: defaultUserID,
						reason: "fourth version",
						createVersion: func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error) {
							companyID := uu.IDMust("32b72879-b489-4d5d-9187-eba8127cc168")
							return newTestMemFiles("b.txt"), []string{"a.txt"}, &companyID, nil
						},
						onNewVersionResultErr: nil,
					},
					wantVersionInfo: &docdb.VersionInfo{
						CompanyID:     uu.IDMust("32b72879-b489-4d5d-9187-eba8127cc168"),
						DocID:         uu.IDFrom("e48162a3-10b2-471b-8feb-adef5bffd279"),
						Version:       versionTime3,
						PrevVersion:   versionTime2,
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
			name:            "onNewVersion returns error",
			createCtx:       docdb.ContextWithVersionTime(context.Background(), versionTime0),
			createCompanyID: defaultCompanyID,
			createDocID:     uu.IDFrom("0a007614-c66c-4af5-97ba-337c32ae2bc2"),
			createUserID:    defaultUserID,
			createReason:    createReason,
			createFiles:     newTestMemFiles("a.txt"),
			calls: []call{
				{
					args: args{
						ctx:    docdb.ContextWithVersionTime(context.Background(), versionTime1),
						docID:  uu.IDFrom("0a007614-c66c-4af5-97ba-337c32ae2bc2"),
						userID: defaultUserID,
						reason: "second version",
						createVersion: func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (writeFiles []fs.FileReader, removeFiles []string, newCompanyID *uu.ID, err error) {
							return newTestMemFiles("b.txt"), nil, nil, nil
						},
						onNewVersionResultErr: testError2,
					},
					wantVersionInfo: nil,
					wantFiles:       nil,
				},
			},
			wantFinalErrIs: testError2,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			lastVersionInfo, err := conn.CreateDocument(
				tt.createCtx,
				tt.createCompanyID,
				tt.createDocID,
				tt.createUserID,
				tt.createReason,
				tt.createFiles,
			)
			require.NoError(t, err)
			require.Equal(t, versionTime0, lastVersionInfo.Version)

			for i, call := range tt.calls {
				var gotVersionInfo *docdb.VersionInfo
				err = conn.AddDocumentVersion(
					call.args.ctx,
					call.args.docID,
					call.args.userID,
					call.args.reason,
					call.args.createVersion,
					func(ctx context.Context, versionInfo *docdb.VersionInfo) error {
						if call.args.onNewVersionResultErr != nil {
							return call.args.onNewVersionResultErr
						}
						gotVersionInfo = versionInfo
						return nil
					},
				)
				require.True(t, gotVersionInfo != nil && err == nil || gotVersionInfo == nil && err != nil)
				// Only last call error is compared with wantFinalErrAs
				// all calls before that must not return an error
				if i < len(tt.calls)-1 {
					require.NoError(t, err)
				}
				require.Equal(t, call.wantVersionInfo, gotVersionInfo)
				if gotVersionInfo != nil {
					require.NoError(t, docdb.CheckConnDocumentVersionFiles(call.args.ctx, conn, call.args.docID, gotVersionInfo.Version, call.wantFiles))
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
