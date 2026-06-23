package storeconn_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

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
