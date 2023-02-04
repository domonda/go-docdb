package hashdb

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-errs"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/uu"
)

// Compiler check if *Conn implements docdb.Conn
var _ docdb.Conn = (*Conn)(nil)

type Conn struct {
	workspaceDir fs.File
	queries      *SQLQueries
	files        FileStore
}

func NewConn(workspaceDir fs.File, queries *SQLQueries, files FileStore) *Conn {
	if !workspaceDir.IsDir() {
		panic("workspaceDir does not exist: '" + string(workspaceDir) + "'")
	}
	if workspaceDir.FileSystem() != fs.Local {
		panic("workspaceDir is not on local file-system: '" + string(workspaceDir) + "'")
	}
	if queries == nil {
		panic("queries is nil")
	}
	return &Conn{
		workspaceDir: workspaceDir,
		queries:      queries,
		files:        files,
	}
}

func (c *Conn) String() string {
	return fmt.Sprintf(
		"hashdb.Conn{Workspace: %q, FileStore: %s}",
		c.workspaceDir.LocalPath(),
		c.files.String(),
	)
}

func (c *Conn) CheckedOutDocumentDir(docID uu.ID) fs.File {
	return c.workspaceDir.Join(docID.String())
}

func (c *Conn) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	return db.QueryValue[bool](ctx, c.queries.DocumentExists, docID)
}

func (c *Conn) EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error {
	return db.QueryRows(ctx, c.queries.AllDocumentIDs).ForEachRowCall(callback)
}

func (c *Conn) EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) (err error) {
	return db.QueryRows(ctx, c.queries.CompanyDocumentIDs, companyID).ForEachRowCall(callback)
}

func (c *Conn) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	companyID, err = db.QueryValue[uu.ID](ctx, c.queries.DocumentCompanyID, docID)
	if err != nil {
		return uu.IDNil, db.ReplaceErrNoRows(err, docdb.NewErrDocumentNotFound(docID))
	}
	return companyID, nil
}

func (c *Conn) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) (err error) {
	_, err = db.QueryValue[bool](ctx, c.queries.SetDocumentCompanyID, docID)
	if err != nil {
		return db.ReplaceErrNoRows(err, docdb.NewErrDocumentNotFound(docID))
	}
	return nil
}

func (c *Conn) DocumentVersions(ctx context.Context, docID uu.ID) (versions []docdb.VersionTime, err error) {
	err = db.QueryRows(ctx, c.queries.DocumentVersions, docID).ScanSlice(&versions)
	if err != nil {
		return nil, err
	}
	return versions, nil
}

func (c *Conn) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (versionInfo *docdb.VersionInfo, err error) {
	versionInfo = &docdb.VersionInfo{
		DocID:   docID,
		Version: version,
	}
	err = db.QueryRow(ctx, c.queries.DocumentVersionInfo, docID, version).Scan(
		&versionInfo.PrevVersion,
		&versionInfo.CommitUserID,
		&versionInfo.CommitReason,
		&versionInfo.Files,
		&versionInfo.AddedFiles,
		&versionInfo.RemovedFiles,
		&versionInfo.ModifiedFiles,
	)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, err
		}
		exists, err := c.DocumentExists(ctx, docID)
		if err != nil {
			return nil, err
		}
		if !exists {
			return nil, docdb.NewErrDocumentNotFound(docID)
		}
		return nil, docdb.NewErrDocumentVersionNotFound(docID, version)
	}
	return versionInfo, nil
}

func (c *Conn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (versionInfo *docdb.VersionInfo, err error) {
	versionInfo = &docdb.VersionInfo{
		DocID: docID,
	}
	err = db.QueryRow(ctx, c.queries.LatestDocumentVersionInfo, docID).Scan(
		&versionInfo.Version,
		&versionInfo.PrevVersion,
		&versionInfo.CommitUserID,
		&versionInfo.CommitReason,
		&versionInfo.Files,
		&versionInfo.AddedFiles,
		&versionInfo.RemovedFiles,
		&versionInfo.ModifiedFiles,
	)
	if err != nil {
		return nil, err
	}
	return versionInfo, nil
}

func (c *Conn) LatestDocumentVersion(ctx context.Context, docID uu.ID) (latest docdb.VersionTime, err error) {
	latest, err = db.QueryValue[docdb.VersionTime](ctx, c.queries.LatestDocumentVersion, docID)
	if err != nil {
		return docdb.VersionTime{}, db.ReplaceErrNoRows(err, docdb.NewErrDocumentNotFound(docID))
	}
	return latest, nil
}

func (c *Conn) documentVersionFileHash(ctx context.Context, docID uu.ID, version docdb.VersionTime, filename string) (hash string, err error) {
	hash, err = db.QueryValue[string](ctx, c.queries.DocumentVersionFileHash, docID, version, filename)
	if err != nil {
		if db.IsOtherThanErrNoRows(err) {
			return "", err
		}
		_, err = c.DocumentVersionInfo(ctx, docID, version)
		if errs.IsErrNotFound(err) {
			return "", err
		}
		return "", docdb.NewErrDocumentFileNotFound(docID, filename)
	}
	return hash, nil
}

func (c *Conn) ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version docdb.VersionTime, filename string) (data []byte, err error) {
	hash, err := c.documentVersionFileHash(ctx, docID, version, filename)
	if err != nil {
		return nil, err
	}
	return c.files.Read(ctx, hash)
}

func (c *Conn) DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version docdb.VersionTime) (p docdb.FileProvider, err error) {
	panic("TODO")
}

func (c *Conn) DocumentCheckOutStatus(ctx context.Context, docID uu.ID) (status *docdb.CheckOutStatus, err error) {
	panic("TODO")
}

func (c *Conn) CheckOutNewDocument(ctx context.Context, docID, companyID, userID uu.ID, reason string) (status *docdb.CheckOutStatus, err error) {
	panic("TODO")
}

func (c *Conn) CheckedOutDocuments(ctx context.Context) (stati []*docdb.CheckOutStatus, err error) {
	panic("TODO")
}

func (c *Conn) CheckOutDocument(ctx context.Context, docID, userID uu.ID, reason string) (checkOutStatus *docdb.CheckOutStatus, err error) {
	panic("TODO")
}

func (c *Conn) removeCheckOutFiles(docID uu.ID) (err error) {
	err = c.CheckedOutDocumentDir(docID).RemoveRecursive()
	return errs.ReplaceErrNotFound(err, nil)
}

func (c *Conn) CancelCheckOutDocument(ctx context.Context, docID uu.ID) (wasCheckedOut bool, lastVersion docdb.VersionTime, err error) {
	panic("TODO")
}

func (c *Conn) CheckInDocument(ctx context.Context, docID uu.ID) (versionInfo *docdb.VersionInfo, err error) {
	panic("TODO")
}

func (c *Conn) DeleteDocument(ctx context.Context, docID uu.ID) (err error) {
	panic("TODO")
}

func (c *Conn) DeleteDocumentVersion(ctx context.Context, docID uu.ID, version docdb.VersionTime) (leftVersions []docdb.VersionTime, err error) {
	panic("TODO")
}
