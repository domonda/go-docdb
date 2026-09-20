// Package ctxflag holds the keys of context flags that more than one package of
// this module has to read.
//
// A flag whose only reader is the package that defines it keeps its key and its
// getter unexported there, which is what every other context switch in this
// module does — see pgstore.ContextWithMetadataStoreVersionsExist and its
// unexported metadataStoreVersionsExist. A flag read across a package boundary
// would have to export its getter to do the same, which is a permanent public
// API commitment made for an intra-module call. The key lives here instead: the
// package that owns the flag keeps the only exported setter, and the package
// that has to act on it reads it from here.
package ctxflag

import "context"

type fileContentWinsOverVersionInfoKey struct{}

// ContextWithFileContentWinsOverVersionInfo returns a context carrying the
// flag. docdb.ContextWithFileContentWinsOverVersionInfo is the exported setter
// and documents what the flag means; nothing outside this module calls this.
func ContextWithFileContentWinsOverVersionInfo(parent context.Context) context.Context {
	return context.WithValue(parent, fileContentWinsOverVersionInfoKey{}, struct{}{})
}

// FileContentWinsOverVersionInfo reports whether ctx was derived from
// ContextWithFileContentWinsOverVersionInfo.
func FileContentWinsOverVersionInfo(ctx context.Context) bool {
	return ctx.Value(fileContentWinsOverVersionInfoKey{}) != nil
}
