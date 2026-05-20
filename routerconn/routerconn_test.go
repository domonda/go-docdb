package routerconn_test

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/routerconn"
	"github.com/domonda/go-types/uu"
)

// connFor builds a routerconn callback that returns backend for wantID
// and fails for any other ID. It serves as both a connForCompanyID and a
// connForDocID callback.
func connFor(wantID uu.ID, backend docdb.Conn) func(context.Context, uu.ID) (docdb.Conn, error) {
	return func(_ context.Context, id uu.ID) (docdb.Conn, error) {
		if id != wantID {
			return nil, errors.New("unexpected ID")
		}
		return backend, nil
	}
}

// unusedConn is a connForCompanyID/connForDocID callback that fails the test if
// it is ever called. Pass it for a callback a test does not exercise (New
// rejects nil callbacks).
func unusedConn(t *testing.T) func(context.Context, uu.ID) (docdb.Conn, error) {
	return func(_ context.Context, id uu.ID) (docdb.Conn, error) {
		t.Errorf("unexpected routing callback called for ID %s", id)
		return nil, errors.New("unused callback called")
	}
}

func TestRouterConn(t *testing.T) {
	t.Run("routes DocumentExists by document ID", func(t *testing.T) {
		docID := uu.IDv7()
		backend := &docdb.MockConn{
			DocumentExistsMock: func(ctx context.Context, id uu.ID) (bool, error) {
				require.Equal(t, docID, id)
				return true, nil
			},
		}
		conn := routerconn.New(unusedConn(t), connFor(docID, backend), backend)

		exists, err := conn.DocumentExists(t.Context(), docID)
		require.NoError(t, err)
		require.True(t, exists)
	})

	t.Run("routes DocumentVersions by document ID", func(t *testing.T) {
		docID := uu.IDv7()
		want := []docdb.VersionTime{docdb.NewVersionTime()}
		backend := &docdb.MockConn{
			DocumentVersionsMock: func(ctx context.Context, id uu.ID) ([]docdb.VersionTime, error) {
				return want, nil
			},
		}
		conn := routerconn.New(unusedConn(t), connFor(docID, backend), backend)

		got, err := conn.DocumentVersions(t.Context(), docID)
		require.NoError(t, err)
		require.Equal(t, want, got)
	})

	t.Run("routes AddDocumentVersion by document ID", func(t *testing.T) {
		docID := uu.IDv7()
		called := false
		backend := &docdb.MockConn{
			AddDocumentVersionMock: func(ctx context.Context, id, userID uu.ID, reason string, createVersion docdb.CreateVersionFunc, onNewVersion docdb.OnNewVersionFunc) error {
				called = true
				require.Equal(t, docID, id)
				return nil
			},
		}
		conn := routerconn.New(unusedConn(t), connFor(docID, backend), backend)

		err := conn.AddDocumentVersion(t.Context(), docID, uu.IDv7(), "reason", nil, nil)
		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("routes CreateDocument by company ID", func(t *testing.T) {
		companyID := uu.IDv7()
		docID := uu.IDv7()
		called := false
		backend := &docdb.MockConn{
			CreateDocumentMock: func(ctx context.Context, cID, id, userID uu.ID, reason string, version docdb.VersionTime, files []fs.FileReader, onNewVersion docdb.OnNewVersionFunc) error {
				called = true
				require.Equal(t, docID, id)
				return nil
			},
		}
		conn := routerconn.New(connFor(companyID, backend), unusedConn(t), backend)

		err := conn.CreateDocument(t.Context(), companyID, docID, uu.IDv7(), "reason", docdb.NewVersionTime(), nil, nil)
		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("routes RestoreDocument by doc.CompanyID", func(t *testing.T) {
		companyID := uu.IDv7()
		called := false
		backend := &docdb.MockConn{
			RestoreDocumentMock: func(ctx context.Context, doc *docdb.HashedDocument, recreate bool) error {
				called = true
				require.Equal(t, companyID, doc.CompanyID)
				return nil
			},
		}
		conn := routerconn.New(connFor(companyID, backend), unusedConn(t), backend)

		err := conn.RestoreDocument(t.Context(), &docdb.HashedDocument{ID: uu.IDv7(), CompanyID: companyID}, false)
		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("routes EnumCompanyDocumentIDs by company ID", func(t *testing.T) {
		companyID := uu.IDv7()
		called := false
		backend := &docdb.MockConn{
			EnumCompanyDocumentIDsMock: func(ctx context.Context, id uu.ID, callback func(context.Context, uu.ID) error) error {
				called = true
				require.Equal(t, companyID, id)
				return nil
			},
		}
		conn := routerconn.New(connFor(companyID, backend), unusedConn(t), backend)

		err := conn.EnumCompanyDocumentIDs(t.Context(), companyID, nil)
		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("EnumDocumentIDs fans out across all backends", func(t *testing.T) {
		docA := uu.IDv7()
		docB := uu.IDv7()
		backendA := &docdb.MockConn{
			EnumDocumentIDsMock: func(ctx context.Context, cb func(context.Context, uu.ID) error) error {
				return cb(ctx, docA)
			},
		}
		backendB := &docdb.MockConn{
			EnumDocumentIDsMock: func(ctx context.Context, cb func(context.Context, uu.ID) error) error {
				return cb(ctx, docB)
			},
		}
		conn := routerconn.New(unusedConn(t), unusedConn(t), backendA, backendB)

		var got []uu.ID
		err := conn.EnumDocumentIDs(t.Context(), func(_ context.Context, id uu.ID) error {
			got = append(got, id)
			return nil
		})
		require.NoError(t, err)
		require.ElementsMatch(t, []uu.ID{docA, docB}, got)
	})

	t.Run("EnumDocumentIDs reports each document once across backends", func(t *testing.T) {
		dup := uu.IDv7()
		enumDup := func(ctx context.Context, cb func(context.Context, uu.ID) error) error {
			return cb(ctx, dup)
		}
		backendA := &docdb.MockConn{EnumDocumentIDsMock: enumDup}
		backendB := &docdb.MockConn{EnumDocumentIDsMock: enumDup}
		conn := routerconn.New(unusedConn(t), unusedConn(t), backendA, backendB)

		var got []uu.ID
		err := conn.EnumDocumentIDs(t.Context(), func(_ context.Context, id uu.ID) error {
			got = append(got, id)
			return nil
		})
		require.NoError(t, err)
		require.Equal(t, []uu.ID{dup}, got)
	})

	t.Run("EnumDocumentIDs propagates a backend error", func(t *testing.T) {
		wantErr := errors.New("backend enum failed")
		backend := &docdb.MockConn{
			EnumDocumentIDsMock: func(ctx context.Context, cb func(context.Context, uu.ID) error) error {
				return wantErr
			},
		}
		conn := routerconn.New(unusedConn(t), unusedConn(t), backend)

		err := conn.EnumDocumentIDs(t.Context(), func(context.Context, uu.ID) error { return nil })
		require.ErrorIs(t, err, wantErr)
	})

	t.Run("AddMultiDocumentVersion routes each document independently", func(t *testing.T) {
		docA := uu.IDv7()
		docB := uu.IDv7()
		var calledA, calledB bool

		addVersion := func(called *bool) func(context.Context, uu.ID, uu.ID, string, docdb.CreateVersionFunc, docdb.OnNewVersionFunc) error {
			return func(ctx context.Context, id, userID uu.ID, reason string, createVersion docdb.CreateVersionFunc, onNewVersion docdb.OnNewVersionFunc) error {
				*called = true
				return onNewVersion(ctx, &docdb.VersionInfo{DocID: id, Version: docdb.NewVersionTime()})
			}
		}
		backendA := &docdb.MockConn{AddDocumentVersionMock: addVersion(&calledA)}
		backendB := &docdb.MockConn{AddDocumentVersionMock: addVersion(&calledB)}

		conn := routerconn.New(
			unusedConn(t),
			func(_ context.Context, id uu.ID) (docdb.Conn, error) {
				switch id {
				case docA:
					return backendA, nil
				case docB:
					return backendB, nil
				default:
					return nil, errors.New("unexpected docID")
				}
			},
			backendA, backendB,
		)

		err := conn.AddMultiDocumentVersion(
			t.Context(),
			uu.IDSlice{docA, docB},
			uu.IDv7(),
			"reason",
			nil,
			func(context.Context, *docdb.VersionInfo) error { return nil },
		)
		require.NoError(t, err)
		require.True(t, calledA)
		require.True(t, calledB)
	})

	t.Run("propagates connForDocID error", func(t *testing.T) {
		wantErr := errors.New("doc routing failed")
		conn := routerconn.New(
			unusedConn(t),
			func(context.Context, uu.ID) (docdb.Conn, error) { return nil, wantErr },
			&docdb.MockConn{},
		)

		_, err := conn.DocumentExists(t.Context(), uu.IDv7())
		require.ErrorIs(t, err, wantErr)
	})

	t.Run("propagates connForCompanyID error", func(t *testing.T) {
		wantErr := errors.New("company routing failed")
		conn := routerconn.New(
			func(context.Context, uu.ID) (docdb.Conn, error) { return nil, wantErr },
			unusedConn(t),
			&docdb.MockConn{},
		)

		err := conn.CreateDocument(t.Context(), uu.IDv7(), uu.IDv7(), uu.IDv7(), "reason", docdb.NewVersionTime(), nil, nil)
		require.ErrorIs(t, err, wantErr)
	})

	t.Run("New panics on a nil callback or no backends", func(t *testing.T) {
		validConn := func(context.Context, uu.ID) (docdb.Conn, error) { return nil, nil }
		backend := &docdb.MockConn{}
		require.Panics(t, func() { routerconn.New(nil, validConn, backend) })
		require.Panics(t, func() { routerconn.New(validConn, nil, backend) })
		require.Panics(t, func() { routerconn.New(validConn, validConn) })
	})
}
