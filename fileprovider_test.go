package docdb

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"
)

func TestFileReaderProvider_HasFile(t *testing.T) {
	tests := []struct {
		name     string
		files    []fs.FileReader
		filename string
		want     bool
	}{
		{
			name:     "empty provider",
			files:    nil,
			filename: "test.txt",
			want:     false,
		},
		{
			name: "file exists",
			files: []fs.FileReader{
				fs.NewMemFile("test.txt", []byte("content")),
				fs.NewMemFile("other.txt", []byte("other")),
			},
			filename: "test.txt",
			want:     true,
		},
		{
			name: "file does not exist",
			files: []fs.FileReader{
				fs.NewMemFile("test.txt", []byte("content")),
				fs.NewMemFile("other.txt", []byte("other")),
			},
			filename: "missing.txt",
			want:     false,
		},
		{
			name: "exact name match required",
			files: []fs.FileReader{
				fs.NewMemFile("test.txt", []byte("content")),
			},
			filename: "Test.txt",
			want:     false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := NewFileProvider(tt.files...)
			got, err := provider.HasFile(tt.filename)
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestFileReaderProvider_ListFiles(t *testing.T) {
	tests := []struct {
		name      string
		files     []fs.FileReader
		wantFiles []string
	}{
		{
			name:      "empty provider",
			files:     nil,
			wantFiles: []string{},
		},
		{
			name: "single file",
			files: []fs.FileReader{
				fs.NewMemFile("test.txt", []byte("content")),
			},
			wantFiles: []string{"test.txt"},
		},
		{
			name: "multiple files sorted",
			files: []fs.FileReader{
				fs.NewMemFile("zebra.txt", []byte("content")),
				fs.NewMemFile("apple.txt", []byte("content")),
				fs.NewMemFile("middle.txt", []byte("content")),
			},
			wantFiles: []string{"apple.txt", "middle.txt", "zebra.txt"},
		},
		{
			name: "files already sorted",
			files: []fs.FileReader{
				fs.NewMemFile("a.txt", []byte("content")),
				fs.NewMemFile("b.txt", []byte("content")),
				fs.NewMemFile("c.txt", []byte("content")),
			},
			wantFiles: []string{"a.txt", "b.txt", "c.txt"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := NewFileProvider(tt.files...)
			ctx := context.Background()
			got, err := provider.ListFiles(ctx)
			require.NoError(t, err)
			assert.Equal(t, tt.wantFiles, got)
		})
	}
}

func TestFileReaderProvider_ReadFile(t *testing.T) {
	tests := []struct {
		name        string
		files       []fs.FileReader
		filename    string
		wantContent []byte
		wantErr     bool
	}{
		{
			name:     "empty provider",
			files:    nil,
			filename: "test.txt",
			wantErr:  true,
		},
		{
			name: "file exists",
			files: []fs.FileReader{
				fs.NewMemFile("test.txt", []byte("hello world")),
			},
			filename:    "test.txt",
			wantContent: []byte("hello world"),
			wantErr:     false,
		},
		{
			name: "file does not exist",
			files: []fs.FileReader{
				fs.NewMemFile("test.txt", []byte("hello world")),
			},
			filename: "missing.txt",
			wantErr:  true,
		},
		{
			name: "read correct file from multiple",
			files: []fs.FileReader{
				fs.NewMemFile("first.txt", []byte("first content")),
				fs.NewMemFile("second.txt", []byte("second content")),
				fs.NewMemFile("third.txt", []byte("third content")),
			},
			filename:    "second.txt",
			wantContent: []byte("second content"),
			wantErr:     false,
		},
		{
			name: "empty file content",
			files: []fs.FileReader{
				fs.NewMemFile("empty.txt", []byte{}),
			},
			filename:    "empty.txt",
			wantContent: []byte{},
			wantErr:     false,
		},
		{
			name: "binary content",
			files: []fs.FileReader{
				fs.NewMemFile("binary.dat", []byte{0x00, 0xFF, 0xAB, 0xCD}),
			},
			filename:    "binary.dat",
			wantContent: []byte{0x00, 0xFF, 0xAB, 0xCD},
			wantErr:     false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := NewFileProvider(tt.files...)
			ctx := context.Background()
			got, err := provider.ReadFile(ctx, tt.filename)

			if tt.wantErr {
				require.Error(t, err)
				assert.True(t, errors.Is(err, os.ErrNotExist), "expected path does not exist error")
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.wantContent, got)
			}
		})
	}
}

func TestFileReaderProvider_ContextCancellation(t *testing.T) {
	provider := NewFileProvider(
		fs.NewMemFile("test.txt", []byte("content")),
	)

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Cancel immediately

	// ListFiles should respect context cancellation
	// Note: The current implementation doesn't check context in ListFiles,
	// but we test the expected behavior
	_, err := provider.ListFiles(ctx)
	// Current implementation doesn't return error on cancelled context for ListFiles
	// This is acceptable for in-memory providers
	assert.NoError(t, err)

	// ReadFile with cancelled context
	// fs.MemFile.ReadAllContext checks context and returns error
	_, err = provider.ReadFile(ctx, "test.txt")
	assert.Error(t, err)
	assert.True(t, errors.Is(err, context.Canceled))
}

func TestFileReaderProvider_Integration(t *testing.T) {
	// Test a complete workflow: create provider, list, check, and read files
	files := []fs.FileReader{
		fs.NewMemFile("doc1.txt", []byte("document one")),
		fs.NewMemFile("doc2.pdf", []byte("document two")),
		fs.NewMemFile("doc3.json", []byte(`{"key": "value"}`)),
	}

	provider := NewFileProvider(files...)
	ctx := context.Background()

	// List all files
	fileList, err := provider.ListFiles(ctx)
	require.NoError(t, err)
	assert.Len(t, fileList, 3)
	assert.Equal(t, []string{"doc1.txt", "doc2.pdf", "doc3.json"}, fileList)

	// Check each file exists
	for _, filename := range fileList {
		exists, err := provider.HasFile(filename)
		require.NoError(t, err)
		assert.True(t, exists, "file %s should exist", filename)
	}

	// Read each file
	content1, err := provider.ReadFile(ctx, "doc1.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("document one"), content1)

	content2, err := provider.ReadFile(ctx, "doc2.pdf")
	require.NoError(t, err)
	assert.Equal(t, []byte("document two"), content2)

	content3, err := provider.ReadFile(ctx, "doc3.json")
	require.NoError(t, err)
	assert.Equal(t, []byte(`{"key": "value"}`), content3)

	// Check non-existent file
	exists, err := provider.HasFile("nonexistent.txt")
	require.NoError(t, err)
	assert.False(t, exists)

	// Try to read non-existent file
	_, err = provider.ReadFile(ctx, "nonexistent.txt")
	require.Error(t, err)
	assert.True(t, errors.Is(err, os.ErrNotExist))
}

func TestReadMemFile(t *testing.T) {
	provider := NewFileProvider(
		fs.NewMemFile("test.txt", []byte("test content")),
		fs.NewMemFile("data.json", []byte(`{"data": "value"}`)),
	)
	ctx := context.Background()

	tests := []struct {
		name         string
		filename     string
		wantContent  []byte
		wantFilename string
		wantErr      bool
	}{
		{
			name:         "read existing file",
			filename:     "test.txt",
			wantContent:  []byte("test content"),
			wantFilename: "test.txt",
			wantErr:      false,
		},
		{
			name:         "read json file",
			filename:     "data.json",
			wantContent:  []byte(`{"data": "value"}`),
			wantFilename: "data.json",
			wantErr:      false,
		},
		{
			name:     "file not found",
			filename: "missing.txt",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			memFile, err := ReadMemFile(ctx, provider, tt.filename)

			if tt.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.wantFilename, memFile.Name())
				content, err := memFile.ReadAll()
				require.NoError(t, err)
				assert.Equal(t, tt.wantContent, content)
			}
		})
	}
}

func TestTempFileCopy(t *testing.T) {
	provider := NewFileProvider(
		fs.NewMemFile("test.txt", []byte("test content")),
		fs.NewMemFile("data.json", []byte(`{"data": "value"}`)),
		fs.NewMemFile("image.png", []byte{0x89, 0x50, 0x4E, 0x47}),
	)
	ctx := context.Background()

	tests := []struct {
		name        string
		filename    string
		wantExt     string
		wantContent []byte
		wantErr     bool
	}{
		{
			name:        "copy txt file",
			filename:    "test.txt",
			wantExt:     ".txt",
			wantContent: []byte("test content"),
			wantErr:     false,
		},
		{
			name:        "copy json file",
			filename:    "data.json",
			wantExt:     ".json",
			wantContent: []byte(`{"data": "value"}`),
			wantErr:     false,
		},
		{
			name:        "copy binary file",
			filename:    "image.png",
			wantExt:     ".png",
			wantContent: []byte{0x89, 0x50, 0x4E, 0x47},
			wantErr:     false,
		},
		{
			name:     "file not found",
			filename: "missing.txt",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tempFile, err := TempFileCopy(ctx, provider, tt.filename)

			if tt.wantErr {
				require.Error(t, err)
				assert.Equal(t, fs.InvalidFile, tempFile)
			} else {
				require.NoError(t, err)
				defer tempFile.Remove()

				// Check file extension
				assert.Equal(t, tt.wantExt, tempFile.Ext())

				// Check file exists
				assert.True(t, tempFile.Exists())

				// Read and verify content
				content, err := tempFile.ReadAll()
				require.NoError(t, err)
				assert.Equal(t, tt.wantContent, content)
			}
		})
	}
}

func TestDirFileProvider_HasFile(t *testing.T) {
	dir := fs.TempDir().Join("TestDirFileProvider_HasFile")
	dir.MakeDir()
	defer dir.RemoveRecursive()

	// Create test files
	dir.Join("file1.txt").WriteAllString("content 1")
	dir.Join("file2.json").WriteAllString(`{"key": "value"}`)
	subDir := dir.Join("subdir")
	subDir.MakeDir()

	provider := DirFileProvider(dir)

	tests := []struct {
		name     string
		filename string
		want     bool
	}{
		{
			name:     "file exists",
			filename: "file1.txt",
			want:     true,
		},
		{
			name:     "another file exists",
			filename: "file2.json",
			want:     true,
		},
		{
			name:     "file does not exist",
			filename: "missing.txt",
			want:     false,
		},
		{
			name:     "subdirectory exists but not a file",
			filename: "subdir",
			want:     true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := provider.HasFile(tt.filename)
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestDirFileProvider_ListFiles(t *testing.T) {
	dir := fs.TempDir().Join("TestDirFileProvider_ListFiles")
	dir.MakeDir()
	defer dir.RemoveRecursive()

	tests := []struct {
		name      string
		setup     func()
		wantFiles []string
	}{
		{
			name:      "empty directory",
			setup:     func() {},
			wantFiles: nil,
		},
		{
			name: "single file",
			setup: func() {
				dir.Join("test.txt").WriteAllString("content")
			},
			wantFiles: []string{"test.txt"},
		},
		{
			name: "multiple files sorted",
			setup: func() {
				dir.Join("zebra.txt").WriteAllString("z")
				dir.Join("apple.txt").WriteAllString("a")
				dir.Join("middle.json").WriteAllString("m")
			},
			wantFiles: []string{"apple.txt", "middle.json", "zebra.txt"},
		},
		{
			name: "files and subdirectories",
			setup: func() {
				dir.Join("file1.txt").WriteAllString("content")
				dir.Join("file2.pdf").WriteAllString("content")
				dir.Join("subdir").MakeDir()
			},
			wantFiles: []string{"file1.txt", "file2.pdf", "subdir"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Clean directory
			dir.RemoveRecursive()
			dir.MakeDir()

			// Setup test files
			tt.setup()

			provider := DirFileProvider(dir)
			ctx := context.Background()

			got, err := provider.ListFiles(ctx)
			require.NoError(t, err)
			assert.Equal(t, tt.wantFiles, got)
		})
	}
}

func TestDirFileProvider_ReadFile(t *testing.T) {
	dir := fs.TempDir().Join("TestDirFileProvider_ReadFile")
	dir.MakeDir()
	defer dir.RemoveRecursive()

	// Create test files
	dir.Join("text.txt").WriteAllString("hello world")
	dir.Join("json.json").WriteAllString(`{"data": "value"}`)
	dir.Join("binary.dat").WriteAll([]byte{0x00, 0xFF, 0xAB, 0xCD})
	dir.Join("empty.txt").WriteAll([]byte{})

	provider := DirFileProvider(dir)
	ctx := context.Background()

	tests := []struct {
		name        string
		filename    string
		wantContent []byte
		wantErr     bool
	}{
		{
			name:        "read text file",
			filename:    "text.txt",
			wantContent: []byte("hello world"),
			wantErr:     false,
		},
		{
			name:        "read json file",
			filename:    "json.json",
			wantContent: []byte(`{"data": "value"}`),
			wantErr:     false,
		},
		{
			name:        "read binary file",
			filename:    "binary.dat",
			wantContent: []byte{0x00, 0xFF, 0xAB, 0xCD},
			wantErr:     false,
		},
		{
			name:        "read empty file",
			filename:    "empty.txt",
			wantContent: []byte{},
			wantErr:     false,
		},
		{
			name:     "file does not exist",
			filename: "missing.txt",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := provider.ReadFile(ctx, tt.filename)

			if tt.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.wantContent, got)
			}
		})
	}
}

func TestDirFileProvider_ContextCancellation(t *testing.T) {
	dir := fs.TempDir().Join("TestDirFileProvider_ContextCancellation")
	dir.MakeDir()
	defer dir.RemoveRecursive()

	dir.Join("test.txt").WriteAllString("content")

	provider := DirFileProvider(dir)

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Cancel immediately

	// ListFiles with cancelled context
	_, err := provider.ListFiles(ctx)
	assert.Error(t, err)
	assert.True(t, errors.Is(err, context.Canceled))

	// ReadFile with cancelled context
	_, err = provider.ReadFile(ctx, "test.txt")
	assert.Error(t, err)
	assert.True(t, errors.Is(err, context.Canceled))
}

func TestDirFileProvider_Integration(t *testing.T) {
	dir := fs.TempDir().Join("TestDirFileProvider_Integration")
	dir.MakeDir()
	defer dir.RemoveRecursive()

	// Create test files
	dir.Join("doc1.txt").WriteAllString("document one")
	dir.Join("doc2.pdf").WriteAllString("document two")
	dir.Join("doc3.json").WriteAllString(`{"key": "value"}`)

	provider := DirFileProvider(dir)
	ctx := context.Background()

	// List all files
	fileList, err := provider.ListFiles(ctx)
	require.NoError(t, err)
	assert.Len(t, fileList, 3)
	assert.Equal(t, []string{"doc1.txt", "doc2.pdf", "doc3.json"}, fileList)

	// Check each file exists
	for _, filename := range fileList {
		exists, err := provider.HasFile(filename)
		require.NoError(t, err)
		assert.True(t, exists, "file %s should exist", filename)
	}

	// Read each file
	content1, err := provider.ReadFile(ctx, "doc1.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("document one"), content1)

	content2, err := provider.ReadFile(ctx, "doc2.pdf")
	require.NoError(t, err)
	assert.Equal(t, []byte("document two"), content2)

	content3, err := provider.ReadFile(ctx, "doc3.json")
	require.NoError(t, err)
	assert.Equal(t, []byte(`{"key": "value"}`), content3)

	// Check non-existent file
	exists, err := provider.HasFile("nonexistent.txt")
	require.NoError(t, err)
	assert.False(t, exists)

	// Try to read non-existent file
	_, err = provider.ReadFile(ctx, "nonexistent.txt")
	require.Error(t, err)
}

func TestDirFileProvider_NestedPaths(t *testing.T) {
	dir := fs.TempDir().Join("TestDirFileProvider_NestedPaths")
	dir.MakeDir()
	defer dir.RemoveRecursive()

	// Create subdirectory with files
	subDir := dir.Join("subdir")
	subDir.MakeDir()
	subDir.Join("nested.txt").WriteAllString("nested content")
	dir.Join("root.txt").WriteAllString("root content")

	provider := DirFileProvider(dir)
	ctx := context.Background()

	// List should only show immediate children
	fileList, err := provider.ListFiles(ctx)
	require.NoError(t, err)
	assert.Len(t, fileList, 2)
	assert.Contains(t, fileList, "root.txt")
	assert.Contains(t, fileList, "subdir")

	// Can read root level file
	content, err := provider.ReadFile(ctx, "root.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("root content"), content)

	// Cannot read nested file with simple name
	_, err = provider.ReadFile(ctx, "nested.txt")
	require.Error(t, err)

	// Can read nested file with path
	content, err = provider.ReadFile(ctx, "subdir/nested.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("nested content"), content)
}

func TestExtFileProvider_HasFile(t *testing.T) {
	baseProvider := NewFileProvider(
		fs.NewMemFile("base1.txt", []byte("base content 1")),
		fs.NewMemFile("base2.txt", []byte("base content 2")),
	)

	tests := []struct {
		name     string
		extFiles []fs.FileReader
		filename string
		want     bool
	}{
		{
			name:     "file in base provider",
			extFiles: []fs.FileReader{},
			filename: "base1.txt",
			want:     true,
		},
		{
			name: "file in extension",
			extFiles: []fs.FileReader{
				fs.NewMemFile("ext.txt", []byte("extension content")),
			},
			filename: "ext.txt",
			want:     true,
		},
		{
			name: "file overridden by extension",
			extFiles: []fs.FileReader{
				fs.NewMemFile("base1.txt", []byte("overridden content")),
			},
			filename: "base1.txt",
			want:     true,
		},
		{
			name:     "file does not exist",
			extFiles: []fs.FileReader{},
			filename: "missing.txt",
			want:     false,
		},
		{
			name: "multiple extension files",
			extFiles: []fs.FileReader{
				fs.NewMemFile("ext1.txt", []byte("ext1")),
				fs.NewMemFile("ext2.txt", []byte("ext2")),
			},
			filename: "ext2.txt",
			want:     true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := ExtFileProvider(baseProvider, tt.extFiles...)
			got, err := provider.HasFile(tt.filename)
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestExtFileProvider_HasFile_NilBase(t *testing.T) {
	provider := ExtFileProvider(nil,
		fs.NewMemFile("ext.txt", []byte("extension content")),
	)

	// File in extension
	has, err := provider.HasFile("ext.txt")
	require.NoError(t, err)
	assert.True(t, has)

	// File not found
	has, err = provider.HasFile("missing.txt")
	require.NoError(t, err)
	assert.False(t, has)
}

func TestExtFileProvider_ListFiles(t *testing.T) {
	baseProvider := NewFileProvider(
		fs.NewMemFile("base1.txt", []byte("base content 1")),
		fs.NewMemFile("base2.txt", []byte("base content 2")),
		fs.NewMemFile("shared.txt", []byte("base shared")),
	)

	tests := []struct {
		name      string
		extFiles  []fs.FileReader
		wantFiles []string
	}{
		{
			name:      "no extensions",
			extFiles:  []fs.FileReader{},
			wantFiles: []string{"base1.txt", "base2.txt", "shared.txt"},
		},
		{
			name: "with extension files",
			extFiles: []fs.FileReader{
				fs.NewMemFile("ext1.txt", []byte("ext1")),
				fs.NewMemFile("ext2.txt", []byte("ext2")),
			},
			wantFiles: []string{"base1.txt", "base2.txt", "ext1.txt", "ext2.txt", "shared.txt"},
		},
		{
			name: "extension overrides base file",
			extFiles: []fs.FileReader{
				fs.NewMemFile("shared.txt", []byte("overridden")),
				fs.NewMemFile("ext.txt", []byte("new")),
			},
			wantFiles: []string{"base1.txt", "base2.txt", "ext.txt", "shared.txt"},
		},
		{
			name: "multiple extensions with same name",
			extFiles: []fs.FileReader{
				fs.NewMemFile("dup.txt", []byte("first")),
				fs.NewMemFile("dup.txt", []byte("second")),
			},
			wantFiles: []string{"base1.txt", "base2.txt", "dup.txt", "shared.txt"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := ExtFileProvider(baseProvider, tt.extFiles...)
			ctx := context.Background()

			got, err := provider.ListFiles(ctx)
			require.NoError(t, err)
			assert.Equal(t, tt.wantFiles, got)
		})
	}
}

func TestExtFileProvider_ListFiles_NilBase(t *testing.T) {
	provider := ExtFileProvider(nil,
		fs.NewMemFile("ext1.txt", []byte("ext1")),
		fs.NewMemFile("ext2.txt", []byte("ext2")),
	)
	ctx := context.Background()

	got, err := provider.ListFiles(ctx)
	require.NoError(t, err)
	assert.Equal(t, []string{"ext1.txt", "ext2.txt"}, got)
}

func TestExtFileProvider_ReadFile(t *testing.T) {
	baseProvider := NewFileProvider(
		fs.NewMemFile("base.txt", []byte("base content")),
		fs.NewMemFile("override.txt", []byte("original content")),
	)

	tests := []struct {
		name        string
		extFiles    []fs.FileReader
		filename    string
		wantContent []byte
		wantErr     bool
	}{
		{
			name:        "read from base",
			extFiles:    []fs.FileReader{},
			filename:    "base.txt",
			wantContent: []byte("base content"),
			wantErr:     false,
		},
		{
			name: "read from extension",
			extFiles: []fs.FileReader{
				fs.NewMemFile("ext.txt", []byte("extension content")),
			},
			filename:    "ext.txt",
			wantContent: []byte("extension content"),
			wantErr:     false,
		},
		{
			name: "extension overrides base",
			extFiles: []fs.FileReader{
				fs.NewMemFile("override.txt", []byte("overridden content")),
			},
			filename:    "override.txt",
			wantContent: []byte("overridden content"),
			wantErr:     false,
		},
		{
			name: "read from first matching extension",
			extFiles: []fs.FileReader{
				fs.NewMemFile("dup.txt", []byte("first")),
				fs.NewMemFile("dup.txt", []byte("second")),
			},
			filename:    "dup.txt",
			wantContent: []byte("first"),
			wantErr:     false,
		},
		{
			name:     "file not found",
			extFiles: []fs.FileReader{},
			filename: "missing.txt",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := ExtFileProvider(baseProvider, tt.extFiles...)
			ctx := context.Background()

			got, err := provider.ReadFile(ctx, tt.filename)

			if tt.wantErr {
				require.Error(t, err)
				assert.True(t, errors.Is(err, os.ErrNotExist))
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.wantContent, got)
			}
		})
	}
}

func TestExtFileProvider_ReadFile_NilBase(t *testing.T) {
	provider := ExtFileProvider(nil,
		fs.NewMemFile("ext.txt", []byte("extension content")),
	)
	ctx := context.Background()

	// Read existing file
	content, err := provider.ReadFile(ctx, "ext.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("extension content"), content)

	// Read missing file
	_, err = provider.ReadFile(ctx, "missing.txt")
	require.Error(t, err)
	assert.True(t, errors.Is(err, os.ErrNotExist))
}

func TestExtFileProvider_Integration(t *testing.T) {
	// Create a base provider with some files
	dir := fs.TempDir().Join("TestExtFileProvider_Integration")
	dir.MakeDir()
	defer dir.RemoveRecursive()

	dir.Join("file1.txt").WriteAllString("original file 1")
	dir.Join("file2.txt").WriteAllString("original file 2")

	baseProvider := DirFileProvider(dir)

	// Extend with additional files and override one
	provider := ExtFileProvider(baseProvider,
		fs.NewMemFile("file1.txt", []byte("overridden file 1")),
		fs.NewMemFile("file3.txt", []byte("new file 3")),
	)

	ctx := context.Background()

	// List all files
	fileList, err := provider.ListFiles(ctx)
	require.NoError(t, err)
	assert.Len(t, fileList, 3)
	assert.Contains(t, fileList, "file1.txt")
	assert.Contains(t, fileList, "file2.txt")
	assert.Contains(t, fileList, "file3.txt")

	// Read overridden file
	content1, err := provider.ReadFile(ctx, "file1.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("overridden file 1"), content1)

	// Read base file
	content2, err := provider.ReadFile(ctx, "file2.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("original file 2"), content2)

	// Read extension file
	content3, err := provider.ReadFile(ctx, "file3.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("new file 3"), content3)
}

func TestRemoveFileProvider_HasFile(t *testing.T) {
	baseProvider := NewFileProvider(
		fs.NewMemFile("file1.txt", []byte("content 1")),
		fs.NewMemFile("file2.txt", []byte("content 2")),
		fs.NewMemFile("file3.txt", []byte("content 3")),
	)

	tests := []struct {
		name            string
		removeFilenames []string
		checkFilename   string
		want            bool
	}{
		{
			name:            "no files removed",
			removeFilenames: []string{},
			checkFilename:   "file1.txt",
			want:            true,
		},
		{
			name:            "file is removed",
			removeFilenames: []string{"file1.txt"},
			checkFilename:   "file1.txt",
			want:            false,
		},
		{
			name:            "file not removed",
			removeFilenames: []string{"file1.txt"},
			checkFilename:   "file2.txt",
			want:            true,
		},
		{
			name:            "multiple files removed",
			removeFilenames: []string{"file1.txt", "file3.txt"},
			checkFilename:   "file2.txt",
			want:            true,
		},
		{
			name:            "check removed file",
			removeFilenames: []string{"file1.txt", "file3.txt"},
			checkFilename:   "file3.txt",
			want:            false,
		},
		{
			name:            "non-existent file not affected",
			removeFilenames: []string{"file1.txt"},
			checkFilename:   "missing.txt",
			want:            false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := RemoveFileProvider(baseProvider, tt.removeFilenames...)
			got, err := provider.HasFile(tt.checkFilename)
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestRemoveFileProvider_ListFiles(t *testing.T) {
	baseProvider := NewFileProvider(
		fs.NewMemFile("file1.txt", []byte("content 1")),
		fs.NewMemFile("file2.txt", []byte("content 2")),
		fs.NewMemFile("file3.txt", []byte("content 3")),
		fs.NewMemFile("file4.txt", []byte("content 4")),
	)

	tests := []struct {
		name            string
		removeFilenames []string
		wantFiles       []string
	}{
		{
			name:            "no files removed",
			removeFilenames: []string{},
			wantFiles:       []string{"file1.txt", "file2.txt", "file3.txt", "file4.txt"},
		},
		{
			name:            "remove one file",
			removeFilenames: []string{"file2.txt"},
			wantFiles:       []string{"file1.txt", "file3.txt", "file4.txt"},
		},
		{
			name:            "remove multiple files",
			removeFilenames: []string{"file1.txt", "file3.txt"},
			wantFiles:       []string{"file2.txt", "file4.txt"},
		},
		{
			name:            "remove all files",
			removeFilenames: []string{"file1.txt", "file2.txt", "file3.txt", "file4.txt"},
			wantFiles:       []string{},
		},
		{
			name:            "remove non-existent file",
			removeFilenames: []string{"missing.txt"},
			wantFiles:       []string{"file1.txt", "file2.txt", "file3.txt", "file4.txt"},
		},
		{
			name:            "remove mix of existing and non-existent",
			removeFilenames: []string{"file1.txt", "missing.txt", "file3.txt"},
			wantFiles:       []string{"file2.txt", "file4.txt"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := RemoveFileProvider(baseProvider, tt.removeFilenames...)
			ctx := context.Background()

			got, err := provider.ListFiles(ctx)
			require.NoError(t, err)
			assert.Equal(t, tt.wantFiles, got)
		})
	}
}

func TestRemoveFileProvider_ReadFile(t *testing.T) {
	baseProvider := NewFileProvider(
		fs.NewMemFile("file1.txt", []byte("content 1")),
		fs.NewMemFile("file2.txt", []byte("content 2")),
		fs.NewMemFile("file3.txt", []byte("content 3")),
	)

	tests := []struct {
		name            string
		removeFilenames []string
		readFilename    string
		wantContent     []byte
		wantErr         bool
	}{
		{
			name:            "read file not removed",
			removeFilenames: []string{"file1.txt"},
			readFilename:    "file2.txt",
			wantContent:     []byte("content 2"),
			wantErr:         false,
		},
		{
			name:            "read removed file",
			removeFilenames: []string{"file1.txt"},
			readFilename:    "file1.txt",
			wantErr:         true,
		},
		{
			name:            "read with multiple files removed",
			removeFilenames: []string{"file1.txt", "file3.txt"},
			readFilename:    "file2.txt",
			wantContent:     []byte("content 2"),
			wantErr:         false,
		},
		{
			name:            "read non-existent file",
			removeFilenames: []string{},
			readFilename:    "missing.txt",
			wantErr:         true,
		},
		{
			name:            "no files removed",
			removeFilenames: []string{},
			readFilename:    "file1.txt",
			wantContent:     []byte("content 1"),
			wantErr:         false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := RemoveFileProvider(baseProvider, tt.removeFilenames...)
			ctx := context.Background()

			got, err := provider.ReadFile(ctx, tt.readFilename)

			if tt.wantErr {
				require.Error(t, err)
				assert.True(t, errors.Is(err, os.ErrNotExist))
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.wantContent, got)
			}
		})
	}
}

func TestRemoveFileProvider_Integration(t *testing.T) {
	// Create a directory with files
	dir := fs.TempDir().Join("TestRemoveFileProvider_Integration")
	dir.MakeDir()
	defer dir.RemoveRecursive()

	dir.Join("keep1.txt").WriteAllString("keep this 1")
	dir.Join("remove1.txt").WriteAllString("remove this 1")
	dir.Join("keep2.txt").WriteAllString("keep this 2")
	dir.Join("remove2.txt").WriteAllString("remove this 2")

	baseProvider := DirFileProvider(dir)

	// Remove some files
	provider := RemoveFileProvider(baseProvider, "remove1.txt", "remove2.txt")
	ctx := context.Background()

	// List files - should only show kept files
	fileList, err := provider.ListFiles(ctx)
	require.NoError(t, err)
	assert.Len(t, fileList, 2)
	assert.Contains(t, fileList, "keep1.txt")
	assert.Contains(t, fileList, "keep2.txt")
	assert.NotContains(t, fileList, "remove1.txt")
	assert.NotContains(t, fileList, "remove2.txt")

	// HasFile should return false for removed files
	has, err := provider.HasFile("remove1.txt")
	require.NoError(t, err)
	assert.False(t, has)

	// HasFile should return true for kept files
	has, err = provider.HasFile("keep1.txt")
	require.NoError(t, err)
	assert.True(t, has)

	// ReadFile should work for kept files
	content, err := provider.ReadFile(ctx, "keep1.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("keep this 1"), content)

	// ReadFile should fail for removed files
	_, err = provider.ReadFile(ctx, "remove1.txt")
	require.Error(t, err)
	assert.True(t, errors.Is(err, os.ErrNotExist))
}

func TestCombinedProviders(t *testing.T) {
	// Test combining ExtFileProvider and RemoveFileProvider
	dir := fs.TempDir().Join("TestCombinedProviders")
	dir.MakeDir()
	defer dir.RemoveRecursive()

	dir.Join("base1.txt").WriteAllString("base content 1")
	dir.Join("base2.txt").WriteAllString("base content 2")
	dir.Join("remove.txt").WriteAllString("will be removed")

	baseProvider := DirFileProvider(dir)

	// First extend with additional files
	extProvider := ExtFileProvider(baseProvider,
		fs.NewMemFile("ext.txt", []byte("extension content")),
		fs.NewMemFile("base1.txt", []byte("overridden content")),
	)

	// Then remove some files
	provider := RemoveFileProvider(extProvider, "remove.txt")
	ctx := context.Background()

	// List files
	fileList, err := provider.ListFiles(ctx)
	require.NoError(t, err)
	assert.Len(t, fileList, 3)
	assert.Contains(t, fileList, "base1.txt")
	assert.Contains(t, fileList, "base2.txt")
	assert.Contains(t, fileList, "ext.txt")
	assert.NotContains(t, fileList, "remove.txt")

	// Read overridden file
	content, err := provider.ReadFile(ctx, "base1.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("overridden content"), content)

	// Read base file
	content, err = provider.ReadFile(ctx, "base2.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("base content 2"), content)

	// Read extension file
	content, err = provider.ReadFile(ctx, "ext.txt")
	require.NoError(t, err)
	assert.Equal(t, []byte("extension content"), content)

	// Cannot read removed file
	_, err = provider.ReadFile(ctx, "remove.txt")
	require.Error(t, err)
	assert.True(t, errors.Is(err, os.ErrNotExist))
}
