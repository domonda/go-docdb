package hashdb

import (
	rootlog "github.com/domonda/golog/log"
)

var (
	log = rootlog.NewPackageLogger("hashdb")
)

type HashFunc func(data []byte) (hash string)
