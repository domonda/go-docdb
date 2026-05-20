// Package routerconn provides a docdb.Conn implementation that routes each
// operation to one of several backend connections.
//
// New takes two routing callbacks plus the full list of backend connections:
//
//   - connForCompanyID maps a company ID to the backend that stores its
//     documents. It routes the operations keyed by a company:
//     EnumCompanyDocumentIDs, CreateDocument (the document does not exist yet)
//     and RestoreDocument.
//   - connForDocID maps a document ID to the backend that stores it. It routes
//     every operation keyed by an existing document.
//   - allConns is the complete list of backend connections; EnumDocumentIDs
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
// Operations keyed by a company - EnumCompanyDocumentIDs, CreateDocument and
// RestoreDocument - are routed through connForCompanyID. Operations keyed by an
// existing document are routed through connForDocID. Both callbacks must return
// one of the allConns connections. EnumDocumentIDs fans out across all of them.
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
	allConns         []docdb.Conn
}

func (r *routerConn) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return false, err
	}
	return conn.DocumentExists(ctx, docID)
}

// EnumDocumentIDs enumerates the documents of every backend in allConns, in the
// order the backends were passed to New.
//
// A document normally lives on a single backend, but EnumDocumentIDs does not
// rely on that: it records every document ID already seen in a uu.IDSet and
// invokes callback at most once per ID, even when more than one backend reports
// the same ID. The set of seen IDs is held in memory until the call returns.
//
// Enumeration stops and returns the error if any backend, or callback itself,
// returns an error.
func (r *routerConn) EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error {
	docIDs := make(uu.IDSet)
	for _, conn := range r.allConns {
		err := conn.EnumDocumentIDs(ctx, func(ctx context.Context, docID uu.ID) error {
			if docIDs.Contains(docID) {
				return nil
			}
			docIDs.Add(docID)
			return callback(ctx, docID)
		})
		if err != nil {
			return err
		}
	}
	return nil
}

func (r *routerConn) EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error {
	conn, err := r.connForCompanyID(ctx, companyID)
	if err != nil {
		return err
	}
	return conn.EnumCompanyDocumentIDs(ctx, companyID, callback)
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
