package localfsdb

import (
	"github.com/domonda/go-types/uu"
	rootlog "github.com/domonda/golog/log"
)

var (
	log = rootlog.NewPackageLogger("localfsdb")

	docMtx = uu.NewIDMutex()
)
