package docdb

import (
	"context"
	"errors"
	"testing"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

func TestReadonlyConn_ReadMethodsForwarded(t *testing.T) {
	ctx := context.Background()
	docID := uu.IDMust("11111111-1111-1111-1111-111111111111")
	companyID := uu.IDMust("22222222-2222-2222-2222-222222222222")

	called := false
	mock := &MockConn{
		DocumentExistsMock: func(ctx context.Context, id uu.ID) (bool, error) {
			called = true
			if id != docID {
				t.Errorf("DocumentExists got docID %s, want %s", id, docID)
			}
			return true, nil
		},
		DocumentCompanyIDMock: func(ctx context.Context, id uu.ID) (uu.ID, error) {
			return companyID, nil
		},
	}

	conn := ReadonlyConn(mock)

	exists, err := conn.DocumentExists(ctx, docID)
	if err != nil {
		t.Fatalf("DocumentExists returned error: %v", err)
	}
	if !exists {
		t.Error("DocumentExists returned false, want true")
	}
	if !called {
		t.Error("DocumentExists was not forwarded to the wrapped Conn")
	}

	gotCompanyID, err := conn.DocumentCompanyID(ctx, docID)
	if err != nil {
		t.Fatalf("DocumentCompanyID returned error: %v", err)
	}
	if gotCompanyID != companyID {
		t.Errorf("DocumentCompanyID got %s, want %s", gotCompanyID, companyID)
	}
}

func TestReadonlyConn_WriteMethodsReturnErrReadonly(t *testing.T) {
	ctx := context.Background()
	docID := uu.IDMust("11111111-1111-1111-1111-111111111111")
	companyID := uu.IDMust("22222222-2222-2222-2222-222222222222")
	userID := uu.IDMust("33333333-3333-3333-3333-333333333333")

	// MockConn with no function fields set: any forwarded write call
	// would panic with a nil func, proving the wrapper never delegates.
	conn := ReadonlyConn(&MockConn{})

	checks := []struct {
		name string
		call func() error
	}{
		{"SetDocumentCompanyID", func() error {
			return conn.SetDocumentCompanyID(ctx, docID, companyID)
		}},
		{"DeleteDocument", func() error {
			return conn.DeleteDocument(ctx, docID)
		}},
		{"DeleteDocumentVersion", func() error {
			_, err := conn.DeleteDocumentVersion(ctx, docID, VersionTime{})
			return err
		}},
		{"CreateDocument", func() error {
			return conn.CreateDocument(ctx, companyID, docID, userID, "reason", VersionTime{}, []fs.FileReader{}, nil)
		}},
		{"AddDocumentVersion", func() error {
			return conn.AddDocumentVersion(ctx, docID, userID, "reason", nil, nil)
		}},
		{"AddMultiDocumentVersion", func() error {
			return conn.AddMultiDocumentVersion(ctx, uu.IDSlice{docID}, userID, "reason", nil, nil)
		}},
		{"RestoreDocument", func() error {
			return conn.RestoreDocument(ctx, &HashedDocument{}, false)
		}},
	}

	for _, check := range checks {
		t.Run(check.name, func(t *testing.T) {
			err := check.call()
			if !errors.Is(err, ErrReadonly) {
				t.Errorf("%s returned %v, want ErrReadonly", check.name, err)
			}
		})
	}
}
