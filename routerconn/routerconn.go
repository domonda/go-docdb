// Package routerconn provides a docdb.Conn implementation that routes each
// operation to one of several backend connections.
//
// New takes two routing callbacks plus the full list of backend connections:
//
//   - connForCompanyID maps a company ID to the backend that stores its
//     documents. It routes the operations keyed by a company:
//     CompanyDocumentIDs, CreateDocument (the document does not exist yet)
//     and RestoreDocument.
//   - connForDocID maps a document ID to the backend that stores it. It routes
//     every operation keyed by an existing document.
//   - allConns is the complete list of backend connections; CompanyIDs
//     fans out across all of them.
//
// A document lives entirely on one backend; routerconn never splits a document
// across backends. Both callbacks must return one of the connections passed as
// allConns, and connForCompanyID and connForDocID must resolve a document and
// its owning company to the same backend.
package routerconn

import (
	"context"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
)

// New returns a docdb.Conn that routes every operation to one of the backend
// connections in allConns.
//
// Operations keyed by a company - CompanyDocumentIDs, CreateDocument and
// RestoreDocument - are routed through connForCompanyID. Operations keyed by an
// existing document are routed through connForDocID. Both callbacks must return
// one of the allConns connections. CompanyIDs fans out across all of them.
//
// New panics if either callback is nil or allConns is empty. An error from
// either callback aborts the operation and is returned unchanged.
func New(
	connForCompanyID func(ctx context.Context, companyID uu.ID) (docdb.Conn, error),
	connForDocID func(ctx context.Context, docID uu.ID) (docdb.Conn, error),
	allConns ...docdb.Conn,
) docdb.Conn {
	if connForCompanyID == nil {
		panic("connForCompanyID is nil")
	}
	if connForDocID == nil {
		panic("connForDocID is nil")
	}
	if len(allConns) == 0 {
		panic("allConns is empty")
	}
	return &routerConn{
		connForCompanyID: connForCompanyID,
		connForDocID:     connForDocID,
		allConns:         allConns,
	}
}

type routerConn struct {
	connForCompanyID func(ctx context.Context, companyID uu.ID) (docdb.Conn, error)
	connForDocID     func(ctx context.Context, docID uu.ID) (docdb.Conn, error)
	allConns         []docdb.Conn // Used for CompanyIDs
}

var _ docdb.Conn = (*routerConn)(nil)

func (r *routerConn) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return false, err
	}
	return conn.DocumentExists(ctx, docID)
}

// CompanyIDs returns the company IDs of every backend in allConns, deduplicated
// and sorted by ID.
//
// A company normally lives on a single backend, but CompanyIDs does not rely on
// that: a company ID reported by more than one backend is returned only once.
// Returns nil if no backend has any companies, and the error of the first
// backend that fails.
func (r *routerConn) CompanyIDs(ctx context.Context) (uu.IDSlice, error) {
	companyIDs := make(uu.IDSet)
	for _, conn := range r.allConns {
		ids, err := conn.CompanyIDs(ctx)
		if err != nil {
			return nil, err
		}
		companyIDs.AddSlice(ids)
	}
	if companyIDs.IsEmpty() {
		return nil, nil
	}
	return companyIDs.AsSortedSlice(), nil
}

func (r *routerConn) CompanyDocumentIDs(ctx context.Context, companyID uu.ID) (uu.IDSlice, error) {
	conn, err := r.connForCompanyID(ctx, companyID)
	if err != nil {
		return nil, err
	}
	return conn.CompanyDocumentIDs(ctx, companyID)
}

func (r *routerConn) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return uu.IDNil, err
	}
	return conn.DocumentCompanyID(ctx, docID)
}

func (r *routerConn) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return err
	}
	return conn.SetDocumentCompanyID(ctx, docID, companyID)
}

func (r *routerConn) DocumentVersions(ctx context.Context, docID uu.ID) ([]docdb.VersionTime, error) {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	return conn.DocumentVersions(ctx, docID)
}

func (r *routerConn) LatestDocumentVersion(ctx context.Context, docID uu.ID) (docdb.VersionTime, error) {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return docdb.VersionTime{}, err
	}
	return conn.LatestDocumentVersion(ctx, docID)
}

func (r *routerConn) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error) {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	return conn.DocumentVersionInfo(ctx, docID, version)
}

func (r *routerConn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*docdb.VersionInfo, error) {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	return conn.LatestDocumentVersionInfo(ctx, docID)
}

func (r *routerConn) DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version docdb.VersionTime) (docdb.FileProvider, error) {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	return conn.DocumentVersionFileProvider(ctx, docID, version)
}

func (r *routerConn) ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version docdb.VersionTime, filename string) (data []byte, err error) {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	return conn.ReadDocumentVersionFile(ctx, docID, version, filename)
}

func (r *routerConn) DeleteDocument(ctx context.Context, docID uu.ID) error {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return err
	}
	return conn.DeleteDocument(ctx, docID)
}

func (r *routerConn) DeleteDocumentVersion(ctx context.Context, docID uu.ID, version docdb.VersionTime) (leftVersions []docdb.VersionTime, err error) {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	return conn.DeleteDocumentVersion(ctx, docID, version)
}

// CreateDocument routes by companyID: the document does not exist yet, so it is
// placed on the backend of its owning company.
func (r *routerConn) CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, version docdb.VersionTime, files []fs.FileReader, onNewVersion docdb.OnNewVersionFunc) error {
	conn, err := r.connForCompanyID(ctx, companyID)
	if err != nil {
		return err
	}
	return conn.CreateDocument(ctx, companyID, docID, userID, reason, version, files, onNewVersion)
}

func (r *routerConn) AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, createVersion docdb.CreateVersionFunc, onNewVersion docdb.OnNewVersionFunc) error {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return err
	}
	return conn.AddDocumentVersion(ctx, docID, userID, reason, createVersion, onNewVersion)
}

func (r *routerConn) AddMultiDocumentVersion(ctx context.Context, docIDs uu.IDSlice, userID uu.ID, reason string, createVersion docdb.CreateVersionFunc, onNewVersion docdb.OnNewVersionFunc) error {
	return docdb.AddMultiDocumentVersionImpl(ctx, r, docIDs, userID, reason, createVersion, onNewVersion)
}

// RestoreDocument routes by doc.CompanyID, consistent with CreateDocument.
func (r *routerConn) RestoreDocument(ctx context.Context, doc *docdb.HashedDocument, recreate bool) error {
	conn, err := r.connForCompanyID(ctx, doc.CompanyID)
	if err != nil {
		return err
	}
	return conn.RestoreDocument(ctx, doc, recreate)
}
