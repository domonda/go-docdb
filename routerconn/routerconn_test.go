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
		want := []docdb.VersionTime{docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")}
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

		err := conn.CreateDocument(t.Context(), companyID, docID, uu.IDv7(), "reason", docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000"), nil, nil)
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

	t.Run("routes CompanyDocumentIDs by company ID", func(t *testing.T) {
		companyID := uu.IDv7()
		docID := uu.IDv7()
		called := false
		backend := &docdb.MockConn{
			CompanyDocumentIDsMock: func(ctx context.Context, id uu.ID) (uu.IDSlice, error) {
				called = true
				require.Equal(t, companyID, id)
				return uu.IDSlice{docID}, nil
			},
		}
		conn := routerconn.New(connFor(companyID, backend), unusedConn(t), backend)

		docIDs, err := conn.CompanyDocumentIDs(t.Context(), companyID)
		require.NoError(t, err)
		require.True(t, called)
		require.Equal(t, uu.IDSlice{docID}, docIDs)
	})

	t.Run("CompanyIDs fans out across all backends", func(t *testing.T) {
		companyA := uu.IDv7()
		companyB := uu.IDv7()
		backendA := &docdb.MockConn{
			CompanyIDsMock: func(ctx context.Context) (uu.IDSlice, error) {
				return uu.IDSlice{companyA}, nil
			},
		}
		backendB := &docdb.MockConn{
			CompanyIDsMock: func(ctx context.Context) (uu.IDSlice, error) {
				return uu.IDSlice{companyB}, nil
			},
		}
		conn := routerconn.New(unusedConn(t), unusedConn(t), backendA, backendB)

		got, err := conn.CompanyIDs(t.Context())
		require.NoError(t, err)
		require.ElementsMatch(t, uu.IDSlice{companyA, companyB}, got)
	})

	t.Run("CompanyIDs reports each company once across backends", func(t *testing.T) {
		dup := uu.IDv7()
		companyIDs := func(ctx context.Context) (uu.IDSlice, error) {
			return uu.IDSlice{dup}, nil
		}
		backendA := &docdb.MockConn{CompanyIDsMock: companyIDs}
		backendB := &docdb.MockConn{CompanyIDsMock: companyIDs}
		conn := routerconn.New(unusedConn(t), unusedConn(t), backendA, backendB)

		got, err := conn.CompanyIDs(t.Context())
		require.NoError(t, err)
		require.Equal(t, uu.IDSlice{dup}, got)
	})

	t.Run("CompanyIDs propagates a backend error", func(t *testing.T) {
		wantErr := errors.New("backend companyIDs failed")
		backend := &docdb.MockConn{
			CompanyIDsMock: func(ctx context.Context) (uu.IDSlice, error) {
				return nil, wantErr
			},
		}
		conn := routerconn.New(unusedConn(t), unusedConn(t), backend)

		_, err := conn.CompanyIDs(t.Context())
		require.ErrorIs(t, err, wantErr)
	})

	t.Run("AddMultiDocumentVersion routes each document independently", func(t *testing.T) {
		docA := uu.IDv7()
		docB := uu.IDv7()
		var calledA, calledB bool

		addVersion := func(called *bool) func(context.Context, uu.ID, uu.ID, string, docdb.CreateVersionFunc, docdb.OnNewVersionFunc) error {
			return func(ctx context.Context, id, userID uu.ID, reason string, createVersion docdb.CreateVersionFunc, onNewVersion docdb.OnNewVersionFunc) error {
				*called = true
				return onNewVersion(ctx, &docdb.VersionInfo{DocID: id, Version: docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")})
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

		err := conn.CreateDocument(t.Context(), uu.IDv7(), uu.IDv7(), uu.IDv7(), "reason", docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000"), nil, nil)
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

// TestRouterConnRefusesCrossBackendCompanyMove covers the ways a document's
// company can change on a router: the two that route by document ID and would
// otherwise commit the change on the backend the document is on while the new
// company belongs to another one, and a restored backup that moves the document
// to a company on another backend, which routes by that company and would
// otherwise copy the document onto it.
//
// routerconn never splits a document across backends, and a document left on
// the backend that no longer answers for its company is not reported as broken
// anywhere: CompanyDocumentIDs of the new company asks the other backend, which
// does not list the document, so a company-wide sync or migration silently
// skips it.
func TestRouterConnRefusesCrossBackendCompanyMove(t *testing.T) {
	var (
		docID     = uu.IDv7()
		companyA  = uu.IDv7() // on backendA, together with the document
		companyB  = uu.IDv7() // on backendB
		newVerion = docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
	)

	newConn := func(t *testing.T, backendA, backendB docdb.Conn) docdb.Conn {
		t.Helper()
		return routerconn.New(
			func(_ context.Context, id uu.ID) (docdb.Conn, error) {
				switch id {
				case companyA:
					return backendA, nil
				case companyB:
					return backendB, nil
				default:
					return nil, errors.New("unexpected companyID")
				}
			},
			connFor(docID, backendA),
			backendA, backendB,
		)
	}

	moveTo := func(companyID uu.ID) docdb.CreateVersionFunc {
		return func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
			return &docdb.CreateVersionResult{Version: newVerion, NewCompanyID: companyID.Nullable()}, nil
		}
	}

	t.Run("AddDocumentVersion to a company on another backend", func(t *testing.T) {
		var committed bool
		backendA := &docdb.MockConn{
			AddDocumentVersionMock: func(ctx context.Context, _, _ uu.ID, _ string, createVersion docdb.CreateVersionFunc, _ docdb.OnNewVersionFunc) error {
				// The company is only known once the callback has run, so the
				// refusal has to come out of the callback — which is what makes
				// the version roll back instead of being committed here.
				_, err := createVersion(ctx, docID, docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000"), nil)
				if err != nil {
					return err
				}
				committed = true
				return nil
			},
		}
		conn := newConn(t, backendA, &docdb.MockConn{})

		err := conn.AddDocumentVersion(t.Context(), docID, uu.IDv7(), "move", moveTo(companyB), nil)
		require.Error(t, err)
		require.ErrorContains(t, err, "routerconn cannot span")
		require.False(t, committed, "the version must not be committed on the document's backend")
	})

	t.Run("AddDocumentVersion to a company on the same backend is allowed", func(t *testing.T) {
		var gotCompanyID uu.NullableID
		backendA := &docdb.MockConn{
			AddDocumentVersionMock: func(ctx context.Context, _, _ uu.ID, _ string, createVersion docdb.CreateVersionFunc, _ docdb.OnNewVersionFunc) error {
				result, err := createVersion(ctx, docID, docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000"), nil)
				if err != nil {
					return err
				}
				gotCompanyID = result.NewCompanyID
				return nil
			},
		}
		conn := newConn(t, backendA, &docdb.MockConn{})

		require.NoError(t, conn.AddDocumentVersion(t.Context(), docID, uu.IDv7(), "move", moveTo(companyA), nil))
		require.Equal(t, companyA.Nullable(), gotCompanyID)
	})

	t.Run("SetDocumentCompanyID to a company on another backend", func(t *testing.T) {
		var called bool
		backendA := &docdb.MockConn{
			SetDocumentCompanyIDMock: func(context.Context, uu.ID, uu.ID) error {
				called = true
				return nil
			},
		}
		conn := newConn(t, backendA, &docdb.MockConn{})

		err := conn.SetDocumentCompanyID(t.Context(), docID, companyB)
		require.Error(t, err)
		require.ErrorContains(t, err, "routerconn cannot span")
		require.False(t, called, "the move must not reach the document's backend")
	})

	t.Run("SetDocumentCompanyID to a company on the same backend is allowed", func(t *testing.T) {
		var called bool
		backendA := &docdb.MockConn{
			SetDocumentCompanyIDMock: func(context.Context, uu.ID, uu.ID) error {
				called = true
				return nil
			},
		}
		conn := newConn(t, backendA, &docdb.MockConn{})

		require.NoError(t, conn.SetDocumentCompanyID(t.Context(), docID, companyA))
		require.True(t, called)
	})
	// RestoreDocument routes by the company of the backup's latest version, so
	// a backup whose newer versions moved the document is routed to the new
	// company's backend — where the document is not, and restoring it there
	// would leave the original behind on the backend it is on.
	t.Run("RestoreDocument of a backup moving the document to another backend", func(t *testing.T) {
		var restored bool
		backendA := &docdb.MockConn{
			DocumentExistsMock: func(_ context.Context, id uu.ID) (bool, error) {
				require.Equal(t, docID, id)
				return true, nil
			},
		}
		backendB := &docdb.MockConn{
			DocumentExistsMock: func(context.Context, uu.ID) (bool, error) { return false, nil },
			RestoreDocumentMock: func(context.Context, *docdb.HashedDocument, bool) error {
				restored = true
				return nil
			},
		}
		conn := newConn(t, backendA, backendB)

		err := conn.RestoreDocument(t.Context(), &docdb.HashedDocument{ID: docID, CompanyID: companyB}, false)
		require.Error(t, err)
		require.ErrorContains(t, err, "routerconn cannot span")
		require.False(t, restored, "the document must not be copied onto the new company's backend")
	})

	t.Run("RestoreDocument of a document no other backend holds is allowed", func(t *testing.T) {
		var restored bool
		notFound := &docdb.MockConn{
			DocumentExistsMock: func(context.Context, uu.ID) (bool, error) { return false, nil },
		}
		backendB := &docdb.MockConn{
			DocumentExistsMock: func(context.Context, uu.ID) (bool, error) { return false, nil },
			RestoreDocumentMock: func(_ context.Context, doc *docdb.HashedDocument, _ bool) error {
				restored = true
				require.Equal(t, companyB, doc.CompanyID)
				return nil
			},
		}
		conn := newConn(t, notFound, backendB)

		// The document exists nowhere yet, which is what every first restore of
		// a document looks like: it is created on its company's backend, the
		// same way CreateDocument creates one.
		require.NoError(t, conn.RestoreDocument(t.Context(), &docdb.HashedDocument{ID: docID, CompanyID: companyB}, false))
		require.True(t, restored)
	})

	t.Run("RestoreDocument into the backend the document is on is allowed", func(t *testing.T) {
		var restored bool
		backendA := &docdb.MockConn{
			DocumentExistsMock: func(context.Context, uu.ID) (bool, error) { return true, nil },
			RestoreDocumentMock: func(context.Context, *docdb.HashedDocument, bool) error {
				restored = true
				return nil
			},
		}
		backendB := &docdb.MockConn{
			DocumentExistsMock: func(context.Context, uu.ID) (bool, error) {
				t.Error("the other backends must not be asked about a document the company's backend holds")
				return false, nil
			},
		}
		conn := newConn(t, backendA, backendB)

		require.NoError(t, conn.RestoreDocument(t.Context(), &docdb.HashedDocument{ID: docID, CompanyID: companyA}, false))
		require.True(t, restored)
	})
}
