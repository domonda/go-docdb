package docdb

import (
	"errors"
	"sync"

	rootlog "github.com/domonda/golog/log"
)

var (
	log = rootlog.NewPackageLogger()

	globalConn    Conn = NewConnWithError(errors.New("docdb connection not configured"))
	globalConnMtx sync.RWMutex
)

// Configure sets the global Conn used by all package-level functions.
// It must be called once at startup before using any document operations.
// Panics if db is nil.
func Configure(db Conn) {
	if db == nil {
		panic("docdb.Configure called with nil Conn")
	}
	globalConnMtx.Lock()
	globalConn = db
	globalConnMtx.Unlock()
}

// GetConn returns the global Conn set by Configure.
func GetConn() Conn {
	globalConnMtx.RLock()
	c := globalConn
	globalConnMtx.RUnlock()
	return c
}
