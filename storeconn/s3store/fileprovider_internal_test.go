package s3store

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
)

// TestNilFileProviderReturnsError pins the nil receiver behaviour of the
// exported methods: a *fileProvider reaches its caller as a docdb.FileProvider
// interface value, where a typed nil is indistinguishable from a real
// provider, so every method has to fail the one call instead of taking down
// the process. It needs no S3 backend.
func TestNilFileProviderReturnsError(t *testing.T) {
	var p *fileProvider

	t.Run("HasFile", func(t *testing.T) {
		_, err := p.HasFile("a.pdf")
		require.ErrorContains(t, err, "nil s3store.fileProvider")
	})

	t.Run("ListFiles", func(t *testing.T) {
		_, err := p.ListFiles(context.Background())
		require.ErrorContains(t, err, "nil s3store.fileProvider")
	})

	t.Run("ReadFile", func(t *testing.T) {
		_, err := p.ReadFile(context.Background(), "a.pdf")
		require.ErrorContains(t, err, "nil s3store.fileProvider")
	})
}
