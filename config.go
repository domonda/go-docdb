package docdb

import (
	"errors"

	rootlog "github.com/domonda/golog/log"
)

var (
	log = rootlog.NewPackageLogger()

	globalConn = NewConnWithError(errors.New("docdb connection not configured"))
)

// Configure sets the global Conn used by all package-level functions.
// It must be called once at startup before using any document operations.
func Configure(db Conn) {
	globalConn = db
}

// GetConn returns the global Conn set by Configure.
func GetConn() Conn { return globalConn }
