package docdb

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"
)

func TestCreateVersionResult_Validate(t *testing.T) {
	validVersion := MustVersionTimeFromString("2023-01-01_00-00-00.000")

	tests := []struct {
		name    string
		result  *CreateVersionResult
		wantErr bool
	}{
		{
			name:    "valid with no files",
			result:  &CreateVersionResult{Version: validVersion},
			wantErr: false,
		},
		{
			name: "valid with WriteFiles only",
			result: &CreateVersionResult{
				Version:    validVersion,
				WriteFiles: []fs.FileReader{fs.NewMemFile("a.txt", []byte("a"))},
			},
			wantErr: false,
		},
		{
			name: "valid with RemoveFiles only",
			result: &CreateVersionResult{
				Version:     validVersion,
				RemoveFiles: []string{"a.txt"},
			},
			wantErr: false,
		},
		{
			name: "valid with disjoint WriteFiles and RemoveFiles",
			result: &CreateVersionResult{
				Version:     validVersion,
				WriteFiles:  []fs.FileReader{fs.NewMemFile("a.txt", []byte("a"))},
				RemoveFiles: []string{"b.txt"},
			},
			wantErr: false,
		},
		{
			name:    "null version",
			result:  &CreateVersionResult{},
			wantErr: true,
		},
		{
			name: "nil WriteFiles entry",
			result: &CreateVersionResult{
				Version:    validVersion,
				WriteFiles: []fs.FileReader{nil},
			},
			wantErr: true,
		},
		{
			name: "non-existent WriteFiles entry",
			result: &CreateVersionResult{
				Version:    validVersion,
				WriteFiles: []fs.FileReader{fs.File("/non/existent/file.txt")},
			},
			wantErr: true,
		},
		{
			name: "same filename in WriteFiles and RemoveFiles",
			result: &CreateVersionResult{
				Version:     validVersion,
				WriteFiles:  []fs.FileReader{fs.NewMemFile("a.txt", []byte("a"))},
				RemoveFiles: []string{"a.txt"},
			},
			wantErr: true,
		},
		{
			name: "multiple files with one overlapping",
			result: &CreateVersionResult{
				Version: validVersion,
				WriteFiles: []fs.FileReader{
					fs.NewMemFile("a.txt", []byte("a")),
					fs.NewMemFile("b.txt", []byte("b")),
				},
				RemoveFiles: []string{"c.txt", "b.txt"},
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.result.Validate()
			if tt.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}
		})
	}
}
