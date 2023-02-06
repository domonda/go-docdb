package hashdb

import (
	"context"
	"fmt"

	"github.com/ungerik/go-fs"
)

type localFileStore struct {
	baseDir  fs.File
	hashFunc HashFunc
}

func NewLocalFileStore(baseDir fs.File, hashFunc HashFunc) (FileStore, error) {
	if err := baseDir.CheckIsDir(); err != nil {
		return nil, err
	}
	return &localFileStore{baseDir, hashFunc}, nil
}

func (l *localFileStore) String() string {
	return l.baseDir.String()
}

func (l *localFileStore) file(hash string) fs.File {
	return l.baseDir.Join(hash)
}

func (l *localFileStore) Create(ctx context.Context, data []byte) (hash string, err error) {
	hash = l.hashFunc(data)
	file := l.file(hash)
	if file.Exists() {
		return hash, fmt.Errorf("hash %s %w", hash, fs.NewErrAlreadyExists(file))
	}
	return hash, file.WriteAllContext(ctx, data)
}

func (l *localFileStore) Delete(ctx context.Context, hash string) error {
	return l.file(hash).Remove()
}

func (l *localFileStore) Read(ctx context.Context, hash string) ([]byte, error) {
	return l.file(hash).ReadAllContext(ctx)
}
