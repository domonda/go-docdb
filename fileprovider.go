package docdb

import (
	"context"

	fs "github.com/ungerik/go-fs"
)

// FileProvider is an interface for read access to named files
type FileProvider interface {
	HasFile(filename string) (bool, error)
	ListFiles(ctx context.Context) (filenames []string, err error)
	ReadFile(ctx context.Context, filename string) ([]byte, error)
}

// DirFileProvider returns a FileProvider for a fs.File directory
func DirFileProvider(dir fs.File) FileProvider {
	return dirFileProvider{dir}
}

type dirFileProvider struct {
	dir fs.File
}

func (d dirFileProvider) HasFile(filename string) (bool, error) {
	return d.dir.Join(filename).Exists(), nil
}

func (d dirFileProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
	err = d.dir.ListDirContext(ctx, func(file fs.File) error {
		filenames = append(filenames, file.Name())
		return nil
	})
	if err != nil {
		return nil, err
	}
	return filenames, nil
}

func (d dirFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	return d.dir.Join(filename).ReadAllContext(ctx)
}

// func MemFileProvider(file fs.MemFile) FileProvider {
// 	return memFileProvider{file}
// }

// type memFileProvider struct {
// 	file fs.MemFile
// }

// func (mem memFileProvider) HasFile(filename string) (bool, error) {
// 	return mem.file.FileName == filename, nil
// }

// func (mem memFileProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
// 	return []string{mem.file.FileName}, nil
// }

// func (mem memFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
// 	if filename != mem.file.FileName {
// 		return nil, fs.NewErrPathDoesNotExist(filename)
// 	}
// 	return mem.file.FileData, nil
// }
