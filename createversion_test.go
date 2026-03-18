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
		{
			name: "null version and nil WriteFiles entry reports multiple errors",
			result: &CreateVersionResult{
				WriteFiles: []fs.FileReader{nil},
			},
			wantErr: true,
		},
		{
			name: "valid with multiple WriteFiles",
			result: &CreateVersionResult{
				Version: validVersion,
				WriteFiles: []fs.FileReader{
					fs.NewMemFile("a.txt", []byte("hello")),
					fs.NewMemFile("b.txt", []byte("world")),
					fs.NewMemFile("c.txt", []byte("!")),
				},
			},
			wantErr: false,
		},
		{
			name: "valid with empty WriteFiles and RemoveFiles slices",
			result: &CreateVersionResult{
				Version:     validVersion,
				WriteFiles:  []fs.FileReader{},
				RemoveFiles: []string{},
			},
			wantErr: false,
		},
		{
			name: "valid with empty file content",
			result: &CreateVersionResult{
				Version:    validVersion,
				WriteFiles: []fs.FileReader{fs.NewMemFile("empty.txt", nil)},
			},
			wantErr: false,
		},
		{
			name: "all WriteFiles overlap with RemoveFiles",
			result: &CreateVersionResult{
				Version: validVersion,
				WriteFiles: []fs.FileReader{
					fs.NewMemFile("x.txt", []byte("x")),
					fs.NewMemFile("y.txt", []byte("y")),
				},
				RemoveFiles: []string{"x.txt", "y.txt"},
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
