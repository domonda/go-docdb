package docdb_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"
	"golang.org/x/exp/maps"
	"golang.org/x/exp/slices"

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
	fileChanges := func(filenames ...string) (files []fs.FileReader) {
		for _, filename := range filenames {
			files = append(files, fs.NewMemFile(filename, []byte(filename))) // Use filename as content
		}
		return files
	}
	fileInfos := func(filenames ...string) map[string]docdb.FileInfo {
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
	var (
		ctx       = context.Background()
		companyID = uu.IDFrom("2fc110fd-ed66-4a8f-9498-4dcb8386d300")
		userID    = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
		reason    = "TestCreateDocument"
	)
	type call struct {
		docID           uu.ID
		files           []fs.FileReader
		wantVersionInfo *docdb.VersionInfo
		wantFiles       []fs.FileReader
	}
	tests := []struct {
		name           string
		calls          []call
		wantFinalErr   bool
		wantFinalErrAs error
	}{
		{
			name:         "invalid input",
			calls:        []call{{}},
			wantFinalErr: true,
		},
		{
			name: "create document without files",
			calls: []call{
				{
					docID: uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171"),
					files: nil,
					wantVersionInfo: &docdb.VersionInfo{
						DocID:        uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171"),
						CommitUserID: userID,
						CommitReason: reason,
					},
					wantFiles: nil,
				},
			},
		},
		{
			name: "create document with 1 file",
			calls: []call{
				{
					docID: uu.IDFrom("a3bf09b6-d2e4-400d-bdf1-fa0a63f934d1"),
					files: fileChanges("a.txt"),
					wantVersionInfo: &docdb.VersionInfo{
						DocID:        uu.IDFrom("a3bf09b6-d2e4-400d-bdf1-fa0a63f934d1"),
						CommitUserID: userID,
						CommitReason: reason,
						Files:        fileInfos("a.txt"),
						AddedFiles:   []string{"a.txt"},
					},
					wantFiles: fileChanges("a.txt"),
				},
			},
		},
		{
			name: "create document with 2 files",
			calls: []call{
				{
					docID: uu.IDFrom("ba4260f6-18c7-4213-8afc-7d041ed7df8d"),
					files: fileChanges("a.txt", "b.txt"),
					wantVersionInfo: &docdb.VersionInfo{
						DocID:        uu.IDFrom("ba4260f6-18c7-4213-8afc-7d041ed7df8d"),
						CommitUserID: userID,
						CommitReason: reason,
						Files:        fileInfos("a.txt", "b.txt"),
						AddedFiles:   []string{"a.txt", "b.txt"},
					},
					wantFiles: fileChanges("a.txt", "b.txt"),
				},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var lastErr error
			for i, c := range tt.calls {
				gotVersionInfo, err := conn.CreateDocument(
					ctx,
					companyID,
					c.docID,
					userID,
					reason,
					c.files,
				)
				// Only last call error is compared with wantFinalErrAs
				// all calls before that must not return an error
				if i < len(tt.calls)-1 {
					require.NoError(t, err)
				}
				require.True(t, equalInfoWithoutVersionTime(gotVersionInfo, c.wantVersionInfo))
				if gotVersionInfo != nil {
					require.NoError(t, docdb.CheckConnDocumentVersionFiles(ctx, conn, c.docID, gotVersionInfo.Version, c.wantFiles))
				}
				lastErr = err
			}
			if tt.wantFinalErrAs != nil {
				require.ErrorAs(t, lastErr, tt.wantFinalErrAs)
				return
			}
			if tt.wantFinalErr {
				require.Error(t, lastErr)
				return
			}
			require.NoError(t, lastErr)
		})
	}
}

// func TestCreateDocumentVersion(t *testing.T) {
// 	conns := []docdb.Conn{
// 		localfsdb.NewTestConn(t),
// 	}
// 	for _, conn := range conns {
// 		testCreateDocumentVersion(t, conn)
// 	}
// }

// func testCreateDocumentVersion(t *testing.T, conn docdb.Conn) {
// 	fileChanges := func(filenames ...string) map[string][]byte {
// 		files := make(map[string][]byte, len(filenames))
// 		for _, filename := range filenames {
// 			files[filename] = []byte(filename) // Use filename as content
// 		}
// 		return files
// 	}
// 	fileInfos := func(filenames ...string) map[string]docdb.FileInfo {
// 		infos := make(map[string]docdb.FileInfo, len(filenames))
// 		for _, filename := range filenames {
// 			// Use filename as content
// 			infos[filename] = docdb.FileInfo{
// 				Name: filename,
// 				Size: int64(len(filename)),
// 				Hash: docdb.ContentHash([]byte(filename)),
// 			}

// 		}
// 		return infos
// 	}
// 	var (
// 		ctx       = context.Background()
// 		companyID = uu.IDFrom("2fc110fd-ed66-4a8f-9498-4dcb8386d300")
// 		userID    = uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171")
// 		reason    = "TestCreateDocumentVersion"
// 	)
// 	type call struct {
// 		docID           uu.ID
// 		baseVersion     docdb.VersionTime
// 		fileChanges     map[string][]byte
// 		onCreate        docdb.OnCreateVersionFunc
// 		wantVersionInfo *docdb.VersionInfo
// 		wantFiles       map[string][]byte
// 	}
// 	tests := []struct {
// 		name           string
// 		calls          []call
// 		wantFinalErr   bool
// 		wantFinalErrAs error
// 	}{
// 		{
// 			name:         "invalid input",
// 			calls:        []call{{}},
// 			wantFinalErr: true,
// 		},
// 		{
// 			name: "create document without files",
// 			calls: []call{
// 				{
// 					docID:       uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171"),
// 					baseVersion: docdb.VersionTime{}, // new document
// 					fileChanges: nil,
// 					onCreate:    nil,
// 					wantVersionInfo: &docdb.VersionInfo{
// 						DocID:        uu.IDFrom("ce6f0867-0172-4ffc-a0c0-c5878b921171"),
// 						CommitUserID: userID,
// 						CommitReason: reason,
// 					},
// 					wantFiles: nil,
// 				},
// 			},
// 		},
// 		{
// 			name: "create document with 1 file",
// 			calls: []call{
// 				{
// 					docID:       uu.IDFrom("a3bf09b6-d2e4-400d-bdf1-fa0a63f934d1"),
// 					baseVersion: docdb.VersionTime{}, // new document
// 					fileChanges: fileChanges("a.txt"),
// 					onCreate:    nil,
// 					wantVersionInfo: &docdb.VersionInfo{
// 						DocID:        uu.IDFrom("a3bf09b6-d2e4-400d-bdf1-fa0a63f934d1"),
// 						CommitUserID: userID,
// 						CommitReason: reason,
// 						Files:        fileInfos("a.txt"),
// 						AddedFiles:   []string{"a.txt"},
// 					},
// 					wantFiles: fileChanges("a.txt"),
// 				},
// 			},
// 		},
// 		{
// 			name: "create document with 2 files",
// 			calls: []call{
// 				{
// 					docID:       uu.IDFrom("ba4260f6-18c7-4213-8afc-7d041ed7df8d"),
// 					baseVersion: docdb.VersionTime{}, // new document
// 					fileChanges: fileChanges("a.txt", "b.txt"),
// 					onCreate:    nil,
// 					wantVersionInfo: &docdb.VersionInfo{
// 						DocID:        uu.IDFrom("ba4260f6-18c7-4213-8afc-7d041ed7df8d"),
// 						CommitUserID: userID,
// 						CommitReason: reason,
// 						Files:        fileInfos("a.txt", "b.txt"),
// 						AddedFiles:   []string{"a.txt", "b.txt"},
// 					},
// 					wantFiles: fileChanges("a.txt", "b.txt"),
// 				},
// 			},
// 		},
// 	}
// 	for _, tt := range tests {
// 		t.Run(tt.name, func(t *testing.T) {
// 			var lastErr error
// 			for i, c := range tt.calls {
// 				gotVersionInfo, err := conn.CreateDocumentVersion(
// 					ctx,
// 					companyID,
// 					c.docID,
// 					userID,
// 					reason,
// 					c.baseVersion,
// 					c.fileChanges,
// 					c.onCreate,
// 				)
// 				// Only last call error is compared with wantFinalErrAs
// 				// all calls before that must not return an error
// 				if i < len(tt.calls)-1 {
// 					require.NoError(t, err)
// 				}
// 				require.True(t, equalInfoWithoutVersionTime(gotVersionInfo, c.wantVersionInfo))
// 				if gotVersionInfo != nil {
// 					require.NoError(t, docdb.CheckConnDocumentVersionFiles(ctx, conn, c.docID, gotVersionInfo.Version, c.wantFiles))
// 				}
// 				lastErr = err
// 			}
// 			if tt.wantFinalErrAs != nil {
// 				require.ErrorAs(t, lastErr, tt.wantFinalErrAs)
// 				return
// 			}
// 			if tt.wantFinalErr {
// 				require.Error(t, lastErr)
// 				return
// 			}
// 			require.NoError(t, lastErr)
// 		})
// 	}
// }

func equalInfoWithoutVersionTime(a, b *docdb.VersionInfo) bool {
	if a == b {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	return a.DocID == b.DocID &&
		a.CommitUserID == b.CommitUserID &&
		a.CommitReason == b.CommitReason &&
		maps.Equal(a.Files, b.Files) &&
		slices.Equal(a.AddedFiles, b.AddedFiles) &&
		slices.Equal(a.RemovedFiles, b.RemovedFiles) &&
		slices.Equal(a.ModifiedFiles, b.ModifiedFiles)
}
