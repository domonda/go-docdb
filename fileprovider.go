package docdb

import (
	"context"

	fs "github.com/ungerik/go-fs"
)

// FileProvider is an interface for read access to named files
type FileProvider interface {
	HasFile(filename string) (bool, error)
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

func (d dirFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	return d.dir.Join(filename).ReadAll(ctx)
}
