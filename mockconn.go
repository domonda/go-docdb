package docdb

import (
	"context"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

type MockConn struct {
	DocumentExistsMock              func(ctx context.Context, docID uu.ID) (exists bool, err error)
	EnumDocumentIDsMock             func(ctx context.Context, callback func(context.Context, uu.ID) error) error
	EnumCompanyDocumentIDsMock      func(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error
	DocumentCompanyIDMock           func(ctx context.Context, docID uu.ID) (companyID uu.ID, err error)
	SetDocumentCompanyIDMock        func(ctx context.Context, docID, companyID uu.ID) error
	DocumentVersionsMock            func(ctx context.Context, docID uu.ID) ([]VersionTime, error)
	LatestDocumentVersionMock       func(ctx context.Context, docID uu.ID) (VersionTime, error)
	DocumentVersionInfoMock         func(ctx context.Context, docID uu.ID, version VersionTime) (*VersionInfo, error)
	LatestDocumentVersionInfoMock   func(ctx context.Context, docID uu.ID) (*VersionInfo, error)
	DocumentVersionFileProviderMock func(ctx context.Context, docID uu.ID, version VersionTime) (FileProvider, error)
	ReadDocumentVersionFileMock     func(ctx context.Context, docID uu.ID, version VersionTime, filename string) (data []byte, err error)
	DeleteDocumentMock              func(ctx context.Context, docID uu.ID) error
	DeleteDocumentVersionMock       func(ctx context.Context, docID uu.ID, version VersionTime) (leftVersions []VersionTime, err error)
	CreateDocumentMock              func(ctx context.Context, companyID, docID, userID uu.ID, reason string, version VersionTime, files []fs.FileReader, onNewVersion OnNewVersionFunc) error
	AddDocumentVersionMock          func(ctx context.Context, docID, userID uu.ID, reason string, version VersionTime, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) error
	RestoreDocumentMock             func(ctx context.Context, doc *HashedDocument, merge bool) error
}

func (mock *MockConn) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	return mock.DocumentExistsMock(ctx, docID)
}
func (mock *MockConn) EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error {
	return mock.EnumDocumentIDsMock(ctx, callback)
}

func (mock *MockConn) EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error {
	return mock.EnumCompanyDocumentIDsMock(ctx, companyID, callback)
}

func (mock *MockConn) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	return mock.DocumentCompanyIDMock(ctx, docID)
}

func (mock *MockConn) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error {
	return mock.SetDocumentCompanyIDMock(ctx, docID, companyID)
}

func (mock *MockConn) DocumentVersions(ctx context.Context, docID uu.ID) ([]VersionTime, error) {
	return mock.DocumentVersionsMock(ctx, docID)
}

func (mock *MockConn) LatestDocumentVersion(ctx context.Context, docID uu.ID) (VersionTime, error) {
	return mock.LatestDocumentVersionMock(ctx, docID)
}

func (mock *MockConn) DocumentVersionInfo(ctx context.Context, docID uu.ID, version VersionTime) (*VersionInfo, error) {
	return mock.DocumentVersionInfoMock(ctx, docID, version)
}

func (mock *MockConn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*VersionInfo, error) {
	return mock.LatestDocumentVersionInfoMock(ctx, docID)
}

func (mock *MockConn) DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version VersionTime) (FileProvider, error) {
	return mock.DocumentVersionFileProviderMock(ctx, docID, version)
}

func (mock *MockConn) ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version VersionTime, filename string) ([]byte, error) {
	return mock.ReadDocumentVersionFileMock(ctx, docID, version, filename)
}

func (mock *MockConn) DeleteDocument(ctx context.Context, docID uu.ID) error {
	return mock.DeleteDocumentMock(ctx, docID)
}

func (mock *MockConn) DeleteDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) ([]VersionTime, error) {
	return mock.DeleteDocumentVersionMock(ctx, docID, version)
}

func (mock *MockConn) CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, version VersionTime, files []fs.FileReader, onNewVersion OnNewVersionFunc) error {
	return mock.CreateDocumentMock(ctx, companyID, docID, userID, reason, version, files, onNewVersion)
}

func (mock *MockConn) AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, version VersionTime, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) error {
	return mock.AddDocumentVersionMock(ctx, docID, userID, reason, version, createVersion, onNewVersion)
}

func (mock *MockConn) RestoreDocument(ctx context.Context, doc *HashedDocument, merge bool) error {
	return mock.RestoreDocumentMock(ctx, doc, merge)
}

var _ Conn = &MockConn{}
