// Package logconn provides a docdb.Conn adapter that logs
// file read and write operations via a configurable golog.Logger.
//
// Every file read, write, and remove is logged with the document ID,
// version, filename, and size in bytes.
package logconn

import (
	"context"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
	"github.com/domonda/golog"
)

// New returns a docdb.Conn that wraps conn and logs all
// file read and write operations to logger.
//
// A nil logger is valid and disables logging while still
// forwarding calls to the wrapped conn.
func New(conn docdb.Conn, logger *golog.Logger) docdb.Conn {
	return &logConn{Conn: conn, log: logger}
}

type logConn struct {
	docdb.Conn
	log *golog.Logger
}

func (c *logConn) DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version docdb.VersionTime) (docdb.FileProvider, error) {
	provider, err := c.Conn.DocumentVersionFileProvider(ctx, docID, version)
	if err != nil {
		return nil, err
	}
	return &logFileProvider{FileProvider: provider, log: c.log, docID: docID, version: version}, nil
}

func (c *logConn) ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version docdb.VersionTime, filename string) ([]byte, error) {
	data, err := c.Conn.ReadDocumentVersionFile(ctx, docID, version, filename)
	if err != nil {
		return nil, err
	}
	c.log.InfoCtx(ctx, "Read file").
		UUID("docID", docID).
		Stringer("version", version).
		Str("filename", filename).
		Int("sizeBytes", len(data)).
		Log()
	return data, nil
}

func (c *logConn) CreateDocument(
	ctx context.Context,
	companyID, docID, userID uu.ID,
	reason string,
	version docdb.VersionTime,
	files []fs.FileReader,
	onNewVersion docdb.OnNewVersionFunc,
) error {
	for _, f := range files {
		c.log.InfoCtx(ctx, "Write file").
			UUID("docID", docID).
			Stringer("version", version).
			Str("filename", f.Name()).
			Int64("sizeBytes", f.Size()).
			Log()
	}
	return c.Conn.CreateDocument(ctx, companyID, docID, userID, reason, version, files, onNewVersion)
}

func (c *logConn) AddDocumentVersion(
	ctx context.Context,
	docID, userID uu.ID,
	reason string,
	createVersion docdb.CreateVersionFunc,
	onNewVersion docdb.OnNewVersionFunc,
) error {
	wrappedCreate := func(ctx context.Context, docID uu.ID, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
		wrappedPrev := &logFileProvider{FileProvider: prevFiles, log: c.log, docID: docID, version: prevVersion}
		result, err := createVersion(ctx, docID, prevVersion, wrappedPrev)
		if err != nil || result == nil {
			return result, err
		}
		for _, wf := range result.WriteFiles {
			c.log.InfoCtx(ctx, "Write file").
				UUID("docID", docID).
				Stringer("version", result.Version).
				Str("filename", wf.Name()).
				Int64("sizeBytes", wf.Size()).
				Log()
		}
		return result, nil
	}
	return c.Conn.AddDocumentVersion(ctx, docID, userID, reason, wrappedCreate, onNewVersion)
}

func (c *logConn) AddMultiDocumentVersion(
	ctx context.Context,
	docIDs uu.IDSlice,
	userID uu.ID,
	reason string,
	createVersion docdb.CreateVersionFunc,
	onNewVersion docdb.OnNewVersionFunc,
) error {
	return docdb.AddMultiDocumentVersionImpl(ctx, c, docIDs, userID, reason, createVersion, onNewVersion)
}

// logFileProvider wraps a docdb.FileProvider and logs
// every ReadFile call including the returned size in bytes.
type logFileProvider struct {
	docdb.FileProvider
	log     *golog.Logger
	docID   uu.ID
	version docdb.VersionTime
}

func (p *logFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	data, err := p.FileProvider.ReadFile(ctx, filename)
	if err != nil {
		return nil, err
	}
	p.log.InfoCtx(ctx, "Read file").
		UUID("docID", p.docID).
		Stringer("version", p.version).
		Str("filename", filename).
		Int("sizeBytes", len(data)).
		Log()
	return data, nil
}

var (
	_ docdb.Conn         = (*logConn)(nil)
	_ docdb.FileProvider = (*logFileProvider)(nil)
)
