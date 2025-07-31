package docdb

import (
	"errors"

	rootlog "github.com/domonda/golog/log"
)

var (
	log = rootlog.NewPackageLogger()

	globalConn = NewConnWithError(errors.New("docdb connection not configured"))
)

// Configure the database connection
func Configure(db Conn) {
	globalConn = db
}

// GetConn returns the configured database connection
func GetConn() Conn { return globalConn }

// func GetDebugFileAccessConnOrNil() DebugFileAccessConn {
// 	d, _ := conn.(DebugFileAccessConn)
// 	return d
// }
