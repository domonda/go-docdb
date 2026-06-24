package docdb

import (
	"sync"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestConfigure(t *testing.T) {
	// Restore the global connection so this test does not leak into others.
	defer func(orig Conn) { globalConn = orig }(globalConn)

	t.Run("panics on nil", func(t *testing.T) {
		require.Panics(t, func() { Configure(nil) })
	})

	t.Run("GetConn returns the configured conn", func(t *testing.T) {
		conn := &MockConn{}
		Configure(conn)
		require.Same(t, conn, GetConn())
	})

	// Run with -race to catch unsynchronized access to the global connection.
	t.Run("concurrent Configure and GetConn", func(t *testing.T) {
		var wg sync.WaitGroup
		for range 50 {
			wg.Add(2)
			go func() { defer wg.Done(); Configure(&MockConn{}) }()
			go func() { defer wg.Done(); _ = GetConn() }()
		}
		wg.Wait()
	})
}
