package storeconn_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/storeconn"
)

// TestConn_RestoreDocument_InvalidDocument verifies that RestoreDocument
// rejects a structurally invalid HashedDocument before touching either store,
// so the nil stores below are never dereferenced.
func TestConn_RestoreDocument_InvalidDocument(t *testing.T) {
	conn := storeconn.New(nil, nil)
	err := conn.RestoreDocument(context.Background(), &docdb.HashedDocument{}, false)
	require.Error(t, err)
}

// TestConn_CreateDocument_RejectsEmptyFiles verifies that a document cannot be
// created without files: its first version must contain at least one file. The
// check runs before either store is accessed, so the nil stores are never
// dereferenced.
func TestConn_CreateDocument_RejectsEmptyFiles(t *testing.T) {
	conn := storeconn.New(nil, nil)
	err := conn.CreateDocument(
		context.Background(),
		uu.IDv4(), uu.IDv4(), uu.IDv4(),
		"reason",
		docdb.NewVersionTime(),
		nil, // no files
		func(context.Context, *docdb.VersionInfo) error { return nil },
	)
	require.Error(t, err)
}
