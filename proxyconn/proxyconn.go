package proxyconn

import (
	"context"
	"errors"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
)

type (
	ConnType        string
	ConfigMap       map[uu.ID]ConnType
	ConfigMapLoader func() (ConfigMap, error)
)

const (
	ConnTypeFS   ConnType = "FS"
	ConnTypeS3PG ConnType = "S3_PG"
)

func NewProxyConn(
	s3PostgresConn,
	fsConn,
	defaultConn docdb.Conn,
	getCompanyIDForDocID func(ctx context.Context, documentID uu.ID) (uu.ID, error),
	loadConfig ConfigMapLoader,
) docdb.Conn {
	return &proxyConn{
		s3PostgresConn:       s3PostgresConn,
		fsConn:               fsConn,
		defaultConn:          defaultConn,
		getCompanyIDForDocID: getCompanyIDForDocID,
		loadConfig:           loadConfig,
	}
}

type proxyConn struct {
	s3PostgresConn       docdb.Conn
	fsConn               docdb.Conn
	defaultConn          docdb.Conn
	getCompanyIDForDocID func(ctx context.Context, documentID uu.ID) (uu.ID, error)
	loadConfig           ConfigMapLoader
}

func (conn *proxyConn) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	companyID, err := conn.getCompanyIDForDocID(ctx, docID)
	if err != nil {
		return false, err
	}
	config, err := conn.loadConfig()
	if err != nil {
		return false, err
	}
	return conn.getConn(config, companyID).DocumentExists(ctx, docID)
}

func (conn *proxyConn) EnumDocumentIDs(
	ctx context.Context,
	callback func(context.Context, uu.ID) error,
) error {
	return errors.New("not_implemented")
}

func (conn *proxyConn) EnumCompanyDocumentIDs(
	ctx context.Context,
	companyID uu.ID,
	callback func(context.Context, uu.ID) error,
) error {
	config, err := conn.loadConfig()
	if err != nil {
		return err
	}
	return conn.getConn(config, companyID).EnumCompanyDocumentIDs(ctx, companyID, callback)
}

func (conn *proxyConn) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	return conn.getCompanyIDForDocID(ctx, docID)
}

func (conn *proxyConn) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error {
	currentCompanyID, err := conn.getCompanyIDForDocID(ctx, docID)
	if err != nil {
		return err
	}
	config, err := conn.loadConfig()
	if err != nil {
		return err
	}
	return conn.getConn(config, currentCompanyID).SetDocumentCompanyID(ctx, docID, companyID)
}

func (conn *proxyConn) DocumentVersions(ctx context.Context, docID uu.ID) ([]docdb.VersionTime, error) {
	companyID, err := conn.getCompanyIDForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	config, err := conn.loadConfig()
	if err != nil {
		return nil, err
	}
	return conn.getConn(config, companyID).DocumentVersions(ctx, docID)
}

func (conn *proxyConn) LatestDocumentVersion(ctx context.Context, docID uu.ID) (docdb.VersionTime, error) {
	companyID, err := conn.getCompanyIDForDocID(ctx, docID)
	if err != nil {
		return docdb.VersionTime{}, err
	}
	config, err := conn.loadConfig()
	if err != nil {
		return docdb.VersionTime{}, err
	}
	return conn.getConn(config, companyID).LatestDocumentVersion(ctx, docID)
}

func (conn *proxyConn) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error) {
	companyID, err := conn.getCompanyIDForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	config, err := conn.loadConfig()
	if err != nil {
		return nil, err
	}
	return conn.getConn(config, companyID).DocumentVersionInfo(ctx, docID, version)
}

func (conn *proxyConn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*docdb.VersionInfo, error) {
	companyID, err := conn.getCompanyIDForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	config, err := conn.loadConfig()
	if err != nil {
		return nil, err
	}
	return conn.getConn(config, companyID).LatestDocumentVersionInfo(ctx, docID)
}

func (conn *proxyConn) DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version docdb.VersionTime) (docdb.FileProvider, error) {
	companyID, err := conn.getCompanyIDForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	config, err := conn.loadConfig()
	if err != nil {
		return nil, err
	}
	return conn.getConn(config, companyID).DocumentVersionFileProvider(ctx, docID, version)
}

func (conn *proxyConn) ReadDocumentVersionFile(
	ctx context.Context,
	docID uu.ID,
	version docdb.VersionTime,
	filename string,
) (data []byte, err error) {
	companyID, err := conn.getCompanyIDForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	config, err := conn.loadConfig()
	if err != nil {
		return nil, err
	}
	return conn.getConn(config, companyID).ReadDocumentVersionFile(ctx, docID, version, filename)
}

func (conn *proxyConn) DeleteDocument(ctx context.Context, docID uu.ID) error {
	companyID, err := conn.getCompanyIDForDocID(ctx, docID)
	if err != nil {
		return err
	}
	config, err := conn.loadConfig()
	if err != nil {
		return err
	}
	return conn.getConn(config, companyID).DeleteDocument(ctx, docID)
}

func (conn *proxyConn) DeleteDocumentVersion(
	ctx context.Context,
	docID uu.ID,
	version docdb.VersionTime,
) (leftVersions []docdb.VersionTime, err error) {
	companyID, err := conn.getCompanyIDForDocID(ctx, docID)
	if err != nil {
		return nil, err
	}
	config, err := conn.loadConfig()
	if err != nil {
		return nil, err
	}
	return conn.getConn(config, companyID).DeleteDocumentVersion(ctx, docID, version)
}

func (conn *proxyConn) CreateDocument(
	ctx context.Context,
	companyID,
	docID,
	userID uu.ID,
	reason string,
	files []fs.FileReader,
) (*docdb.VersionInfo, error) {
	config, err := conn.loadConfig()
	if err != nil {
		return nil, err
	}
	return conn.getConn(config, companyID).CreateDocument(ctx, companyID, docID, userID, reason, files)
}

func (conn *proxyConn) AddDocumentVersion(
	ctx context.Context,
	docID,
	userID uu.ID,
	reason string,
	createVersion docdb.CreateVersionFunc,
	onNewVersion docdb.OnNewVersionFunc,
) error {
	companyID, err := conn.getCompanyIDForDocID(ctx, docID)
	if err != nil {
		return err
	}
	config, err := conn.loadConfig()
	if err != nil {
		return err
	}
	return conn.getConn(config, companyID).AddDocumentVersion(ctx, docID, userID, reason, createVersion, onNewVersion)
}

func (conn *proxyConn) RestoreDocument(
	ctx context.Context,
	doc *docdb.HashedDocument,
	merge bool,
) error {
	config, err := conn.loadConfig()
	if err != nil {
		return err
	}
	return conn.getConn(config, doc.CompanyID).RestoreDocument(ctx, doc, merge)
}

func (conn *proxyConn) getConn(config ConfigMap, companyID uu.ID) docdb.Conn {
	connType, ok := config[companyID]
	if !ok {
		return conn.defaultConn
	}

	switch connType {
	case ConnTypeFS:
		return conn.fsConn
	case ConnTypeS3PG:
		return conn.s3PostgresConn
	default:
		return conn.defaultConn
	}
}
