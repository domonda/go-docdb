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
//
// connForDocID must also resolve a document ID it has never seen to the backend
// that would hold it, rather than failing. DocumentExists is the one routed
// operation asked about documents that may exist nowhere, and it answers from
// the backend the callback names; a callback that errors on an unknown ID turns
// "this document does not exist" into an error instead of the (false, nil) the
// docdb.Conn contract calls for.
//
// Every backend must be reachable for RestoreDocument. It is the one operation
// routed by company that can create a document, so before restoring it asks the
// other backends whether any of them already holds it — the check that keeps a
// document from ending up on two backends. A backend that cannot answer leaves
// that unresolved, so the restore is refused rather than risking the split. The
// other operations are routed and never fan out, so an unreachable backend only
// affects the documents on it.
//
// Changing a document's company is therefore refused when the new company
// resolves to another backend: for SetDocumentCompanyID, for a version that
// names a docdb.CreateVersionResult.NewCompanyID, and for a RestoreDocument
// whose backup moves the document to such a company while another backend still
// holds it. Moving a document to a company on another backend is a migration —
// every version copied over and the original deleted — not a company change,
// and doing the company change alone would leave the document on a backend that
// no longer answers for its company.
package routerconn

import (
	"context"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-errs"
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

// DocumentExists answers from the backend connForDocID names for docID, which
// is authoritative because a document lives on exactly one backend. It is the
// one routed operation asked about documents that may exist nowhere, so the
// callback has to name a backend for an ID it has never seen; see the package
// doc. (false, nil) is that backend's answer, and a backend that could not be
// asked returns its error rather than a "no".
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
	if err = r.checkCompanyOnConn(ctx, docID, companyID, conn); err != nil {
		return err
	}
	return conn.SetDocumentCompanyID(ctx, docID, companyID)
}

// checkCompanyOnConn returns an error if moving docID to companyID would leave
// the document on a backend that is not the one connForCompanyID resolves its
// new company to.
//
// routerconn never splits a document across backends and its callbacks must
// resolve a document and its owning company to the same one (see the package
// doc). A move to a company on another backend breaks that: the document stays
// where it is while CompanyDocumentIDs of the new company asks the other
// backend, which does not list it — so a company-wide sync or migration skips
// it without reporting anything. Carrying the document over would be a copy of
// every version plus a delete of the original, which is a migration, not a
// company change; refusing tells the caller to run one instead of silently
// stranding the document.
//
// The backends are compared by identity, which is what the package already
// requires of the callbacks: both must return one of the connections passed as
// allConns.
func (r *routerConn) checkCompanyOnConn(ctx context.Context, docID, companyID uu.ID, docConn docdb.Conn) error {
	companyConn, err := r.connForCompanyID(ctx, companyID)
	if err != nil {
		return err
	}
	if companyConn != docConn {
		return errCrossBackendMove(docID, companyID, companyConn, docConn)
	}
	return nil
}

// errCrossBackendMove reports a document that would end up on docConn while its
// company is answered by companyConn.
//
// The backends are reported by type, not by value: a backend prints its whole
// configuration when it has no String method of its own.
func errCrossBackendMove(docID, companyID uu.ID, companyConn, docConn docdb.Conn) error {
	return errs.Errorf(
		"cannot move document %s to company %s: the company routes to backend %T but the document is on backend %T, and routerconn cannot span the two — migrate the document instead",
		docID, companyID, companyConn, docConn,
	)
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

// AddDocumentVersion routes by docID, and refuses a version that would move the
// document to a company on another backend.
//
// A version can change the document's company via
// docdb.CreateVersionResult.NewCompanyID, which docdb.Conn documents as the way
// to move a document between companies. That company is only known once
// createVersion has run, so the check is wrapped around the callback rather
// than done up front: returning the error from there aborts the version and
// rolls back atomically, leaving the document where it is instead of committed
// on the wrong backend.
func (r *routerConn) AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, createVersion docdb.CreateVersionFunc, onNewVersion docdb.OnNewVersionFunc) error {
	conn, err := r.connForDocID(ctx, docID)
	if err != nil {
		return err
	}
	if createVersion != nil {
		inner := createVersion
		createVersion = func(ctx context.Context, docID uu.ID, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
			result, err := inner(ctx, docID, prevVersion, prevFiles)
			if err != nil || result == nil {
				return result, err
			}
			if result.NewCompanyID.IsNotNull() {
				if err = r.checkCompanyOnConn(ctx, docID, result.NewCompanyID.Get(), conn); err != nil {
					return nil, err
				}
			}
			return result, nil
		}
	}
	return conn.AddDocumentVersion(ctx, docID, userID, reason, createVersion, onNewVersion)
}

func (r *routerConn) AddMultiDocumentVersion(ctx context.Context, docIDs uu.IDSlice, userID uu.ID, reason string, createVersion docdb.CreateVersionFunc, onNewVersion docdb.OnNewVersionFunc) error {
	return docdb.AddMultiDocumentVersionImpl(ctx, r, docIDs, userID, reason, createVersion, onNewVersion)
}

// RestoreDocument routes by doc.CompanyID, consistent with CreateDocument, and
// refuses a backup that would leave a second copy of the document on another
// backend.
//
// doc.CompanyID is the company of the backup's latest version, which can be one
// the document was moved to after this router last saw it: a backup whose newer
// versions move the document is restored as that move rather than refused as a
// company mismatch (see docdb.CheckRestoreCompanyID). Restoring it on the new
// company's backend while the original stays where it is splits the document
// across backends, which routerconn never does — and neither copy is reported
// as wrong anywhere afterwards: every operation keyed by the document keeps
// going to the backend connForDocID names, while the other one answers
// CompanyDocumentIDs for the company the backup moved it to.
func (r *routerConn) RestoreDocument(ctx context.Context, doc *docdb.HashedDocument, recreate bool) error {
	conn, err := r.connForCompanyID(ctx, doc.CompanyID)
	if err != nil {
		return err
	}
	otherConn, err := r.otherConnWithDocument(ctx, doc.ID, conn)
	if err != nil {
		return err
	}
	if otherConn != nil {
		return errCrossBackendMove(doc.ID, doc.CompanyID, conn, otherConn)
	}
	return conn.RestoreDocument(ctx, doc, recreate)
}

// otherConnWithDocument returns the backend other than docConn that holds
// docID, or nil if none does.
//
// It answers the question connForDocID answers for every other operation, by
// asking the backends instead of the callback: RestoreDocument routes by
// company and can create the document, and connForDocID cannot be asked about a
// document that does not exist yet — the reason CreateDocument routes by
// company as well.
//
// The other backends are only asked when docConn does not already hold the
// document, which is the common case of a merge-restore into the backend the
// document is on, and not at all for a router over a single backend, where
// nothing can span.
//
// A backend that cannot answer aborts the search. This is the one place a
// caller pays for another backend being unreachable, and it is deliberate: the
// question is whether some other backend already holds the document, and an
// unreachable one leaves that unanswered. Restoring anyway would risk the
// split across backends this package promises never to make, so an
// unanswerable question is an error rather than a "no". Before the backends
// grew the ability to say so, an unreadable one answered (false, nil) and the
// restore went ahead on an answer nobody had.
func (r *routerConn) otherConnWithDocument(ctx context.Context, docID uu.ID, docConn docdb.Conn) (docdb.Conn, error) {
	if len(r.allConns) == 1 {
		return nil, nil
	}
	exists, err := docConn.DocumentExists(ctx, docID)
	if err != nil || exists {
		return nil, err
	}
	for _, conn := range r.allConns {
		if conn == docConn {
			continue
		}
		exists, err = conn.DocumentExists(ctx, docID)
		if err != nil {
			return nil, err
		}
		if exists {
			return conn, nil
		}
	}
	return nil, nil
}
