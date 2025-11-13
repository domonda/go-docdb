package proxyconn_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb/proxyconn"
)

func TestProxyConn(t *testing.T) {
	t.Run("DocumentExists selects proper conn", func(t *testing.T) {
		// given
		companyID1 := uu.IDv7()
		companyID2 := uu.IDv7()
		docID := uu.IDv7()

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID1: proxyconn.ConnTypeFS,
				companyID2: proxyconn.ConnTypeS3PG,
			}, nil
		}

		s3Conn := &docdb.MockConn{
			DocumentExistsMock: func(ctx context.Context, docID uu.ID) (exists bool, err error) {
				return true, nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID != docID {
				return uu.IDNil, errors.New("not_found")
			}

			return companyID2, nil
		}

		conn := proxyconn.NewProxyConn(
			s3Conn,
			nil,
			nil,
			getCompanyIDForDocID,
			getConfig,
		)

		// when
		res, err := conn.DocumentExists(t.Context(), docID)

		// then
		require.NoError(t, err)
		require.True(t, res)
	})

	t.Run("EnumCompanyDocumentIDs selects proper conn", func(t *testing.T) {
		// given
		companyID1 := uu.IDv7()
		companyID2 := uu.IDv7()

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID1: proxyconn.ConnTypeFS,
				companyID2: proxyconn.ConnTypeS3PG,
			}, nil
		}

		called := false
		fsConn := &docdb.MockConn{
			EnumCompanyDocumentIDsMock: func(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error {
				called = true
				return nil
			},
		}
		var s3Conn docdb.Conn
		conn := proxyconn.NewProxyConn(
			s3Conn,
			fsConn,
			s3Conn,
			nil,
			getConfig,
		)

		// when
		err := conn.EnumCompanyDocumentIDs(t.Context(), companyID1, nil)
		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("DocumentCompanyID returns company ID", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID == docID {
				return companyID, nil
			}
			return uu.IDNil, errors.New("not_found")
		}

		conn := proxyconn.NewProxyConn(nil, nil, nil, getCompanyIDForDocID, nil)

		// when
		result, err := conn.DocumentCompanyID(t.Context(), docID)

		// then
		require.NoError(t, err)
		require.Equal(t, companyID, result)
	})

	t.Run("SetDocumentCompanyID selects proper conn", func(t *testing.T) {
		// given
		oldCompanyID := uu.IDv7()
		newCompanyID := uu.IDv7()
		docID := uu.IDv7()

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				oldCompanyID: proxyconn.ConnTypeFS,
			}, nil
		}

		called := false
		fsConn := &docdb.MockConn{
			SetDocumentCompanyIDMock: func(ctx context.Context, docID, companyID uu.ID) error {
				called = true
				require.Equal(t, newCompanyID, companyID)
				return nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID == docID {
				return oldCompanyID, nil
			}
			return uu.IDNil, errors.New("not_found")
		}

		conn := proxyconn.NewProxyConn(nil, fsConn, nil, getCompanyIDForDocID, getConfig)

		// when
		err := conn.SetDocumentCompanyID(t.Context(), docID, newCompanyID)

		// then
		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("DocumentVersions selects proper conn", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()
		version1 := docdb.VersionTime{Time: time.Now().Add(-1 * time.Hour)}
		version2 := docdb.VersionTime{Time: time.Now()}

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID: proxyconn.ConnTypeS3PG,
			}, nil
		}

		s3Conn := &docdb.MockConn{
			DocumentVersionsMock: func(ctx context.Context, docID uu.ID) ([]docdb.VersionTime, error) {
				return []docdb.VersionTime{version1, version2}, nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID == docID {
				return companyID, nil
			}
			return uu.IDNil, errors.New("not_found")
		}

		conn := proxyconn.NewProxyConn(s3Conn, nil, nil, getCompanyIDForDocID, getConfig)

		// when
		versions, err := conn.DocumentVersions(t.Context(), docID)

		// then
		require.NoError(t, err)
		require.Len(t, versions, 2)
		require.Equal(t, version1, versions[0])
		require.Equal(t, version2, versions[1])
	})

	t.Run("LatestDocumentVersion selects proper conn", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()
		latestVersion := docdb.VersionTime{Time: time.Now()}

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID: proxyconn.ConnTypeFS,
			}, nil
		}

		fsConn := &docdb.MockConn{
			LatestDocumentVersionMock: func(ctx context.Context, docID uu.ID) (docdb.VersionTime, error) {
				return latestVersion, nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID == docID {
				return companyID, nil
			}
			return uu.IDNil, errors.New("not_found")
		}

		conn := proxyconn.NewProxyConn(nil, fsConn, nil, getCompanyIDForDocID, getConfig)

		// when
		version, err := conn.LatestDocumentVersion(t.Context(), docID)

		// then
		require.NoError(t, err)
		require.Equal(t, latestVersion, version)
	})

	t.Run("DocumentVersionInfo selects proper conn", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()
		userID := uu.IDv7()
		version := docdb.VersionTime{Time: time.Now()}
		expectedInfo := &docdb.VersionInfo{
			CompanyID:    companyID,
			DocID:        docID,
			Version:      version,
			CommitUserID: userID,
			CommitReason: "test reason",
		}

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID: proxyconn.ConnTypeS3PG,
			}, nil
		}

		s3Conn := &docdb.MockConn{
			DocumentVersionInfoMock: func(ctx context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error) {
				return expectedInfo, nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID == docID {
				return companyID, nil
			}
			return uu.IDNil, errors.New("not_found")
		}

		conn := proxyconn.NewProxyConn(s3Conn, nil, nil, getCompanyIDForDocID, getConfig)

		// when
		info, err := conn.DocumentVersionInfo(t.Context(), docID, version)

		// then
		require.NoError(t, err)
		require.Equal(t, expectedInfo, info)
	})

	t.Run("LatestDocumentVersionInfo selects proper conn", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()
		userID := uu.IDv7()
		expectedInfo := &docdb.VersionInfo{
			CompanyID:    companyID,
			DocID:        docID,
			Version:      docdb.VersionTime{Time: time.Now()},
			CommitUserID: userID,
			CommitReason: "latest version",
		}

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID: proxyconn.ConnTypeFS,
			}, nil
		}

		fsConn := &docdb.MockConn{
			LatestDocumentVersionInfoMock: func(ctx context.Context, docID uu.ID) (*docdb.VersionInfo, error) {
				return expectedInfo, nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID == docID {
				return companyID, nil
			}
			return uu.IDNil, errors.New("not_found")
		}

		conn := proxyconn.NewProxyConn(nil, fsConn, nil, getCompanyIDForDocID, getConfig)

		// when
		info, err := conn.LatestDocumentVersionInfo(t.Context(), docID)

		// then
		require.NoError(t, err)
		require.Equal(t, expectedInfo, info)
	})

	t.Run("DocumentVersionFileProvider selects proper conn", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()
		version := docdb.VersionTime{Time: time.Now()}
		mockProvider := &mockFileProvider{}

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID: proxyconn.ConnTypeS3PG,
			}, nil
		}

		s3Conn := &docdb.MockConn{
			DocumentVersionFileProviderMock: func(ctx context.Context, docID uu.ID, version docdb.VersionTime) (docdb.FileProvider, error) {
				return mockProvider, nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID == docID {
				return companyID, nil
			}
			return uu.IDNil, errors.New("not_found")
		}

		conn := proxyconn.NewProxyConn(s3Conn, nil, nil, getCompanyIDForDocID, getConfig)

		// when
		provider, err := conn.DocumentVersionFileProvider(t.Context(), docID, version)

		// then
		require.NoError(t, err)
		require.Equal(t, mockProvider, provider)
	})

	t.Run("ReadDocumentVersionFile selects proper conn", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()
		version := docdb.VersionTime{Time: time.Now()}
		filename := "test.txt"
		expectedData := []byte("test content")

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID: proxyconn.ConnTypeFS,
			}, nil
		}

		fsConn := &docdb.MockConn{
			ReadDocumentVersionFileMock: func(ctx context.Context, docID uu.ID, version docdb.VersionTime, filename string) ([]byte, error) {
				return expectedData, nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID == docID {
				return companyID, nil
			}
			return uu.IDNil, errors.New("not_found")
		}

		conn := proxyconn.NewProxyConn(nil, fsConn, nil, getCompanyIDForDocID, getConfig)

		// when
		data, err := conn.ReadDocumentVersionFile(t.Context(), docID, version, filename)

		// then
		require.NoError(t, err)
		require.Equal(t, expectedData, data)
	})

	t.Run("DeleteDocument selects proper conn", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID: proxyconn.ConnTypeS3PG,
			}, nil
		}

		called := false
		s3Conn := &docdb.MockConn{
			DeleteDocumentMock: func(ctx context.Context, docID uu.ID) error {
				called = true
				return nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID == docID {
				return companyID, nil
			}
			return uu.IDNil, errors.New("not_found")
		}

		conn := proxyconn.NewProxyConn(s3Conn, nil, nil, getCompanyIDForDocID, getConfig)

		// when
		err := conn.DeleteDocument(t.Context(), docID)

		// then
		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("DeleteDocumentVersion selects proper conn", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()
		version := docdb.VersionTime{Time: time.Now()}
		leftVersions := []docdb.VersionTime{{Time: time.Now().Add(-1 * time.Hour)}}

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID: proxyconn.ConnTypeFS,
			}, nil
		}

		fsConn := &docdb.MockConn{
			DeleteDocumentVersionMock: func(ctx context.Context, docID uu.ID, version docdb.VersionTime) ([]docdb.VersionTime, error) {
				return leftVersions, nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID == docID {
				return companyID, nil
			}
			return uu.IDNil, errors.New("not_found")
		}

		conn := proxyconn.NewProxyConn(nil, fsConn, nil, getCompanyIDForDocID, getConfig)

		// when
		result, err := conn.DeleteDocumentVersion(t.Context(), docID, version)

		// then
		require.NoError(t, err)
		require.Equal(t, leftVersions, result)
	})

	t.Run("CreateDocument selects proper conn", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()
		userID := uu.IDv7()
		reason := "create document"
		files := []fs.FileReader{fs.NewMemFile("test.txt", []byte("content"))}

		expectedInfo := &docdb.VersionInfo{
			CompanyID:    companyID,
			DocID:        docID,
			CommitUserID: userID,
			CommitReason: reason,
		}

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID: proxyconn.ConnTypeS3PG,
			}, nil
		}

		s3Conn := &docdb.MockConn{
			CreateDocumentMock: func(ctx context.Context, companyID, docID, userID uu.ID, reason string, files []fs.FileReader) (*docdb.VersionInfo, error) {
				return expectedInfo, nil
			},
		}

		conn := proxyconn.NewProxyConn(s3Conn, nil, nil, nil, getConfig)

		// when
		info, err := conn.CreateDocument(t.Context(), companyID, docID, userID, reason, files)

		// then
		require.NoError(t, err)
		require.Equal(t, expectedInfo, info)
	})

	t.Run("AddDocumentVersion selects proper conn", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()
		userID := uu.IDv7()
		reason := "add version"

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID: proxyconn.ConnTypeFS,
			}, nil
		}

		called := false
		fsConn := &docdb.MockConn{
			AddDocumentVersionMock: func(ctx context.Context, docID, userID uu.ID, reason string, createVersion docdb.CreateVersionFunc, onNewVersion docdb.OnNewVersionFunc) error {
				called = true
				return nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			if documentID == docID {
				return companyID, nil
			}
			return uu.IDNil, errors.New("not_found")
		}

		conn := proxyconn.NewProxyConn(nil, fsConn, nil, getCompanyIDForDocID, getConfig)

		// when
		err := conn.AddDocumentVersion(t.Context(), docID, userID, reason, nil, nil)

		// then
		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("RestoreDocument selects proper conn", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()
		doc := &docdb.HashedDocument{
			ID:        docID,
			CompanyID: companyID,
		}

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{
				companyID: proxyconn.ConnTypeS3PG,
			}, nil
		}

		called := false
		s3Conn := &docdb.MockConn{
			RestoreDocumentMock: func(ctx context.Context, doc *docdb.HashedDocument, merge bool) error {
				called = true
				return nil
			},
		}

		conn := proxyconn.NewProxyConn(s3Conn, nil, nil, nil, getConfig)

		// when
		err := conn.RestoreDocument(t.Context(), doc, false)

		// then
		require.NoError(t, err)
		require.True(t, called)
	})

	t.Run("uses default conn when company not in config", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return proxyconn.ConfigMap{}, nil
		}

		called := false
		defaultConn := &docdb.MockConn{
			DocumentExistsMock: func(ctx context.Context, docID uu.ID) (exists bool, err error) {
				called = true
				return true, nil
			},
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			return companyID, nil
		}

		conn := proxyconn.NewProxyConn(nil, nil, defaultConn, getCompanyIDForDocID, getConfig)

		// when
		res, err := conn.DocumentExists(t.Context(), docID)

		// then
		require.NoError(t, err)
		require.True(t, res)
		require.True(t, called)
	})

	t.Run("handles config loading error", func(t *testing.T) {
		// given
		companyID := uu.IDv7()
		docID := uu.IDv7()
		expectedErr := errors.New("config load error")

		var getConfig proxyconn.ConfigMapLoader = func() (proxyconn.ConfigMap, error) {
			return nil, expectedErr
		}

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			return companyID, nil
		}

		conn := proxyconn.NewProxyConn(nil, nil, nil, getCompanyIDForDocID, getConfig)

		// when
		_, err := conn.DocumentExists(t.Context(), docID)

		// then
		require.Error(t, err)
		require.Equal(t, expectedErr, err)
	})

	t.Run("handles getCompanyIDForDocID error", func(t *testing.T) {
		// given
		docID := uu.IDv7()
		expectedErr := errors.New("company ID lookup error")

		getCompanyIDForDocID := func(ctx context.Context, documentID uu.ID) (uu.ID, error) {
			return uu.IDNil, expectedErr
		}

		conn := proxyconn.NewProxyConn(nil, nil, nil, getCompanyIDForDocID, nil)

		// when
		_, err := conn.DocumentExists(t.Context(), docID)

		// then
		require.Error(t, err)
		require.Equal(t, expectedErr, err)
	})
}

// mockFileProvider is a simple mock implementation of docdb.FileProvider
type mockFileProvider struct{}

func (m *mockFileProvider) ListFiles(ctx context.Context) ([]string, error) {
	return []string{"test.txt"}, nil
}

func (m *mockFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	return []byte("test content"), nil
}

func (m *mockFileProvider) HasFile(filename string) (bool, error) {
	return filename == "test.txt", nil
}
