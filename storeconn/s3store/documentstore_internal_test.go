package s3store

import (
	"testing"

	"github.com/stretchr/testify/require"
)

// TestFilterKeysByHash is a pure unit test for the unexported helper used by
// DocumentHashFileProvider and DeleteDocumentHashes. It needs no S3 backend.
func TestFilterKeysByHash(t *testing.T) {
	keys := []string{
		"doc/a.pdf/h1",
		"doc/b.pdf/h2",
		"doc/c.pdf/h3",
	}

	t.Run("Returns only keys whose hash matches", func(t *testing.T) {
		got := filterKeysByHash(keys, []string{"h1", "h3"})
		require.Equal(t, []string{"doc/a.pdf/h1", "doc/c.pdf/h3"}, got)
	})

	t.Run("Returns each matching key at most once despite duplicate hashes", func(t *testing.T) {
		got := filterKeysByHash(keys, []string{"h2", "h2", "h2"})
		require.Equal(t, []string{"doc/b.pdf/h2"}, got)
	})

	t.Run("Returns nil when no hash matches", func(t *testing.T) {
		got := filterKeysByHash(keys, []string{"missing"})
		require.Nil(t, got)
	})

	t.Run("Returns nil for empty hashes", func(t *testing.T) {
		got := filterKeysByHash(keys, nil)
		require.Nil(t, got)
	})
}
