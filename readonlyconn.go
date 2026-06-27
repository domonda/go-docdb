package docdb

import (
	"context"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

// ReadonlyConn wraps the passed Conn so that all read methods are
// forwarded to it while all write methods return ErrReadonly without
// touching the underlying connection.
func ReadonlyConn(conn Conn) Conn { return readonlyConn{conn} }

// readonlyConn wraps a Conn and returns ErrReadonly from every write method.
type readonlyConn struct {
	Conn
}

var _ Conn = readonlyConn{}

func (c readonlyConn) SetDocumentCompanyID(_ context.Context, docID, companyID uu.ID) error {
	return errs.Errorf("cannot set company %s for document %s: %w", companyID, docID, ErrReadonly)
}

func (c readonlyConn) DeleteDocument(_ context.Context, docID uu.ID) error {
	return errs.Errorf("cannot delete document %s: %w", docID, ErrReadonly)
}

func (c readonlyConn) DeleteDocumentVersion(_ context.Context, docID uu.ID, version VersionTime) (leftVersions []VersionTime, err error) {
	return nil, errs.Errorf("cannot delete version %s of document %s: %w", version, docID, ErrReadonly)
}

func (c readonlyConn) CreateDocument(_ context.Context, companyID, docID, _ uu.ID, _ string, _ VersionTime, _ []fs.FileReader, _ OnNewVersionFunc) error {
	return errs.Errorf("cannot create document %s for company %s: %w", docID, companyID, ErrReadonly)
}

func (c readonlyConn) AddDocumentVersion(_ context.Context, docID, _ uu.ID, _ string, _ CreateVersionFunc, _ OnNewVersionFunc) error {
	return errs.Errorf("cannot add version to document %s: %w", docID, ErrReadonly)
}

func (c readonlyConn) AddMultiDocumentVersion(_ context.Context, docIDs uu.IDSlice, _ uu.ID, _ string, _ CreateVersionFunc, _ OnNewVersionFunc) error {
	return errs.Errorf("cannot add version to documents %s: %w", docIDs, ErrReadonly)
}

func (c readonlyConn) RestoreDocument(_ context.Context, doc *HashedDocument, _ bool) error {
	var docID uu.ID
	if doc != nil {
		docID = doc.ID
	}
	return errs.Errorf("cannot restore document %s: %w", docID, ErrReadonly)
}
