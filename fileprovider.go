package docdb

import (
	"context"
	"path"
	"slices"

	"github.com/ungerik/go-fs"
)

// FileProvider is an interface for read access to named files
type FileProvider interface {
	HasFile(filename string) (bool, error)
	ListFiles(ctx context.Context) (filenames []string, err error)
	ReadFile(ctx context.Context, filename string) ([]byte, error)
}

func NewFileProvider(files ...fs.FileReader) FileProvider {
	return fileReaderProvider(files)
}

type fileReaderProvider []fs.FileReader

func (p fileReaderProvider) HasFile(filename string) (bool, error) {
	return slices.ContainsFunc(p, func(f fs.FileReader) bool {
		return f.Name() == filename
	}), nil
}

func (p fileReaderProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
	filenames = make([]string, len(p))
	for i, f := range p {
		filenames[i] = f.Name()
	}
	slices.Sort(filenames)
	return filenames, nil
}

func (p fileReaderProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	for _, f := range p {
		if f.Name() == filename {
			return f.ReadAllContext(ctx)
		}
	}
	return nil, fs.NewErrPathDoesNotExist(filename)
}

// ReadMemFile reads a file from a FileProvider and returns it as an fs.MemFile.
func ReadMemFile(ctx context.Context, provider FileProvider, filename string) (fs.MemFile, error) {
	data, err := provider.ReadFile(ctx, filename)
	if err != nil {
		return fs.MemFile{}, err
	}
	return fs.NewMemFile(filename, data), nil
}

// TempFileCopy reads a file from a FileProvider and writes it to a temporary file
// with a random basename and the same extension as the original filename.
func TempFileCopy(ctx context.Context, provider FileProvider, filename string) (fs.File, error) {
	data, err := provider.ReadFile(ctx, filename)
	if err != nil {
		return fs.InvalidFile, err
	}
	f := fs.TempFile(path.Ext(filename))
	return f, f.WriteAllContext(ctx, data)
}

///////////////////////////////////////////////////////////////////////////////
// DirFileProvider

// DirFileProvider returns a FileProvider for a fs.File directory
func DirFileProvider(dir fs.File) FileProvider {
	return dirFileProvider{dir}
}

type dirFileProvider struct {
	dir fs.File
}

func (p dirFileProvider) HasFile(filename string) (bool, error) {
	return p.dir.Join(filename).Exists(), nil
}

func (p dirFileProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
	err = p.dir.ListDirContext(ctx, func(file fs.File) error {
		filenames = append(filenames, file.Name())
		return nil
	})
	if err != nil {
		return nil, err
	}
	slices.Sort(filenames)
	return filenames, nil
}

func (p dirFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	return p.dir.Join(filename).ReadAllContext(ctx)
}

///////////////////////////////////////////////////////////////////////////////
// ExtFileProvider

// ExtFileProvider returns a FileProvider that extends a base FileProvider
// with additional files that will be returned before the files of the base FileProvider.
func ExtFileProvider(base FileProvider, extFiles ...fs.FileReader) FileProvider {
	return extFileProvider{base, extFiles}
}

type extFileProvider struct {
	base     FileProvider
	extFiles []fs.FileReader
}

func (p extFileProvider) HasFile(filename string) (bool, error) {
	for _, f := range p.extFiles {
		if f.Name() == filename {
			return true, nil
		}
	}
	if p.base == nil {
		return false, nil
	}
	return p.base.HasFile(filename)
}

func (p extFileProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
	if p.base != nil {
		filenames, err = p.base.ListFiles(ctx)
		if err != nil {
			return nil, err
		}
	}
	for _, f := range p.extFiles {
		if !slices.Contains(filenames, f.Name()) {
			filenames = append(filenames, f.Name())
		}
	}
	slices.Sort(filenames)
	return filenames, nil
}

func (p extFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	for _, f := range p.extFiles {
		if f.Name() == filename {
			return f.ReadAllContext(ctx)
		}
	}
	if p.base == nil {
		return nil, fs.NewErrPathDoesNotExist(filename)
	}
	return p.base.ReadFile(ctx, filename)
}

///////////////////////////////////////////////////////////////////////////////
// RemoveFileProvider

// RemoveFileProvider returns a FileProvider that wraps a base FileProvider
// and does not return files with the passed removeFilenames.
func RemoveFileProvider(base FileProvider, removeFilenames ...string) FileProvider {
	return &removeFileProvider{base, removeFilenames}
}

type removeFileProvider struct {
	base   FileProvider
	remove []string
}

func (p *removeFileProvider) HasFile(filename string) (bool, error) {
	if slices.Contains(p.remove, filename) {
		return false, nil
	}
	return p.base.HasFile(filename)
}

func (p removeFileProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
	filenames, err = p.base.ListFiles(ctx)
	if err != nil {
		return nil, err
	}
	filenames = slices.DeleteFunc(filenames, func(filename string) bool {
		return slices.Contains(p.remove, filename)
	})
	return filenames, nil
}

func (p removeFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	if slices.Contains(p.remove, filename) {
		return nil, fs.NewErrPathDoesNotExist(filename)
	}
	return p.base.ReadFile(ctx, filename)
}

///////////////////////////////////////////////////////////////////////////////

type MockFileProvider struct {
	HasFileMock   func(filename string) (bool, error)
	ListFilesMock func(ctx context.Context) (filenames []string, err error)
	ReadFileMock  func(ctx context.Context, filename string) ([]byte, error)
}

func (fp *MockFileProvider) HasFile(filename string) (bool, error) {
	return fp.HasFileMock(filename)
}

func (fp *MockFileProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
	return fp.ListFilesMock(ctx)
}

func (fp *MockFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	return fp.ReadFileMock(ctx, filename)
}

var _ FileProvider = &MockFileProvider{}

var _ FileProvider = memFileProvider{}

// SingleMemFileProvider returns a FileProvider that contains a single MemFile.
func SingleMemFileProvider(file fs.MemFile) FileProvider {
	return memFileProvider{file}
}

type memFileProvider struct {
	file fs.MemFile
}

func (mem memFileProvider) HasFile(filename string) (bool, error) {
	return mem.file.FileName == filename, nil
}

func (mem memFileProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
	return []string{mem.file.FileName}, nil
}

func (mem memFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	if filename != mem.file.FileName {
		return nil, fs.NewErrPathDoesNotExist(filename)
	}
	return mem.file.FileData, nil
}
