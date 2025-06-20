package hashdb

import (
	rootlog "github.com/domonda/golog/log"
)

var (
	log = rootlog.NewPackageLogger()
)

type HashFunc func(data []byte) (hash string)
