package hashdb

import (
	"context"
	"fmt"
)

type FileStore interface {
	fmt.Stringer

	Create(ctx context.Context, data []byte) (hash string, err error)
	Delete(ctx context.Context, hash string) error
	Read(ctx context.Context, hash string) ([]byte, error)
}
