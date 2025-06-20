package localfsdb

import (
	"github.com/domonda/go-types/uu"
	rootlog "github.com/domonda/golog/log"
)

var (
	log = rootlog.NewPackageLogger()

	docWriteMtx = uu.NewIDMutex()
)
