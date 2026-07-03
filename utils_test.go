package docdb

import (
	"context"
	"testing"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestIdenticalDocumentVersionsOfDrivers(t *testing.T) {
	ctx := context.Background()
	docID := uu.IDMustFromString("11111111-2222-3333-4444-555555555555")
	versionA := MustVersionTimeFromString("2026-03-23_14-19-22.200")
	versionB := MustVersionTimeFromString("2026-03-24_09-00-00.000")

	// connReturning builds a Conn whose DocumentVersionInfo yields info/err.
	connReturning := func(info *VersionInfo, err error) Conn {
		return &MockConn{
			DocumentVersionInfoMock: func(context.Context, uu.ID, VersionTime) (*VersionInfo, error) {
				return info, err
			},
		}
	}

	t.Run("driverA error propagates", func(t *testing.T) {
		driverA := connReturning(nil, errs.New("driverA failed"))
		driverB := connReturning(baseVersionInfo(), nil)

		identical, err := IdenticalDocumentVersionsOfDrivers(ctx, docID, driverA, versionA, driverB, versionB)

		require.Error(t, err)
		assert.False(t, identical)
	})

	t.Run("driverB error propagates", func(t *testing.T) {
		driverA := connReturning(baseVersionInfo(), nil)
		driverB := connReturning(nil, errs.New("driverB failed"))

		identical, err := IdenticalDocumentVersionsOfDrivers(ctx, docID, driverA, versionA, driverB, versionB)

		require.Error(t, err)
		assert.False(t, identical)
	})

	t.Run("versions identical except change-slice order", func(t *testing.T) {
		// The regression this change fixes: the two drivers return the same
		// version whose added/removed/modified sets differ only in order.
		// reflect.DeepEqual reported these as different; Equal reports them
		// identical.
		infoA := baseVersionInfo()
		infoB := cloneVersionInfo(baseVersionInfo())
		infoB.AddedFiles = []string{"b.pdf", "a.pdf"}
		infoB.RemovedFiles = []string{"old2.pdf", "old1.pdf"}
		infoB.ModifiedFiles = []string{"m2.pdf", "m1.pdf"}

		identical, err := IdenticalDocumentVersionsOfDrivers(ctx, docID, connReturning(infoA, nil), versionA, connReturning(infoB, nil), versionB)

		require.NoError(t, err)
		assert.True(t, identical)
	})

	t.Run("genuinely different versions", func(t *testing.T) {
		infoA := baseVersionInfo()
		infoB := cloneVersionInfo(baseVersionInfo())
		infoB.CommitReason = "a different reason"

		identical, err := IdenticalDocumentVersionsOfDrivers(ctx, docID, connReturning(infoA, nil), versionA, connReturning(infoB, nil), versionB)

		require.NoError(t, err)
		assert.False(t, identical)
	})

	t.Run("both drivers return nil info", func(t *testing.T) {
		// A driver returning (nil, nil) is treated as identical to another
		// driver also returning (nil, nil) — no panic on the nil receiver.
		identical, err := IdenticalDocumentVersionsOfDrivers(ctx, docID, connReturning(nil, nil), versionA, connReturning(nil, nil), versionB)

		require.NoError(t, err)
		assert.True(t, identical)
	})
}
