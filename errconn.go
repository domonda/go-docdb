package docdb

import (
	"context"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

// NewConnWithError returns a Conn where all
// methods return the passed error.
func NewConnWithError(err error) Conn { return errConn{err} }

// errConn implements the Conn interface
// by returning an error from every method.
type errConn struct {
	err error
}

func (c errConn) DocumentExists(context.Context, uu.ID) (bool, error) {
	return false, c.err
}

func (c errConn) EnumDocumentIDs(context.Context, func(context.Context, uu.ID) error) error {
	return c.err
}

func (c errConn) EnumCompanyDocumentIDs(context.Context, uu.ID, func(context.Context, uu.ID) error) error {
	return c.err
}

func (c errConn) DocumentCompanyID(context.Context, uu.ID) (uu.ID, error) {
	return uu.IDNil, c.err
}

func (c errConn) SetDocumentCompanyID(context.Context, uu.ID, uu.ID) (err error) {
	return c.err
}

func (c errConn) DocumentVersions(context.Context, uu.ID) ([]VersionTime, error) {
	return nil, c.err
}

func (c errConn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (versionInfo *VersionInfo, err error) {
	return nil, c.err
}

func (c errConn) LatestDocumentVersion(context.Context, uu.ID) (VersionTime, error) {
	return VersionTime{}, c.err
}

func (c errConn) DocumentVersionInfo(context.Context, uu.ID, VersionTime) (*VersionInfo, error) {
	return nil, c.err
}

func (c errConn) DocumentVersionFileProvider(context.Context, uu.ID, VersionTime) (FileProvider, error) {
	return nil, c.err
}

func (c errConn) ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version VersionTime, filename string) (data []byte, err error) {
	return nil, c.err
}

func (c errConn) DocumentCheckOutStatus(context.Context, uu.ID) (*CheckOutStatus, error) {
	return nil, c.err
}

func (c errConn) CheckedOutDocuments(context.Context) ([]*CheckOutStatus, error) {
	return nil, c.err
}

func (c errConn) CheckOutNewDocument(context.Context, uu.ID, uu.ID, uu.ID, string) (*CheckOutStatus, error) {
	return nil, c.err
}

func (c errConn) CheckOutDocument(context.Context, uu.ID, uu.ID, string) (*CheckOutStatus, error) {
	return nil, c.err
}

func (c errConn) CancelCheckOutDocument(context.Context, uu.ID) (bool, VersionTime, error) {
	return false, VersionTime{}, c.err
}

func (c errConn) CheckInDocument(context.Context, uu.ID) (*VersionInfo, error) {
	return nil, c.err
}

func (c errConn) CheckedOutDocumentDir(uu.ID) fs.File {
	return fs.InvalidFile
}

func (c errConn) DeleteDocument(context.Context, uu.ID) error {
	return c.err
}

func (c errConn) DeleteDocumentVersion(context.Context, uu.ID, VersionTime) ([]VersionTime, error) {
	return nil, c.err
}

func (c errConn) InsertDocumentVersion(context.Context, uu.ID, VersionTime, uu.ID, string, []fs.FileReader) (*VersionInfo, error) {
	return nil, c.err
}

// func (c errConn) DebugGetDocumentDir(uu.ID) fs.File {
// 	return fs.InvalidFile
// }

// func (c errConn) DebugGetDocumentVersionFile(uu.ID, VersionTime, string) (fs.File, error) {
// 	return fs.InvalidFile, c.err
// }

func (c errConn) CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, files []fs.FileReader, onNewVersion OnNewVersionFunc) error {
	return c.err
}

func (c errConn) AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) error {
	return c.err
}

func (c errConn) RestoreDocument(ctx context.Context, doc *HashedDocument, merge bool) error {
	return c.err
}
