package docdb

import (
	"bytes"
	"context"
	"errors"

	"github.com/domonda/go-errs"
	rootlog "github.com/domonda/golog/log"
	"github.com/ungerik/go-fs/fsimpl"
)

var (
	log = rootlog.NewPackageLogger("docdb")

	conn = NewConnWithError(errors.New("docdb connection not configured"))
)

// Configure the database connection
func Configure(db Conn) {
	conn = db
}

// GetConn returns the configured database connection
func GetConn() Conn { return conn }

func GetDebugFileAccessConnOrNil() DebugFileAccessConn {
	d, _ := conn.(DebugFileAccessConn)
	return d
}

// ContentHash returns a Dropbox compatible 64 hex character content hash
// by reading from an io.Reader until io.EOF.
// See https://www.dropbox.com/developers/reference/content-hash
func ContentHash(data []byte) string {
	hash, err := fsimpl.DropboxContentHash(context.Background(), bytes.NewReader(data))
	if err != nil {
		panic(errs.Errorf("should never happen: %w", err))
	}
	return hash
}
