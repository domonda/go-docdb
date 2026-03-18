package docdb

import (
	"bytes"
	"context"
	"reflect"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

// IdenticalDocumentVersionsOfDrivers returns true if the specified versions
// of a document have identical VersionInfo across two different Conn implementations.
func IdenticalDocumentVersionsOfDrivers(ctx context.Context, docID uu.ID, driverA Conn, versionA VersionTime, driverB Conn, versionB VersionTime) (identical bool, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, driverA, versionA, driverB, versionB)

	fileInfosA, err := driverA.DocumentVersionInfo(ctx, docID, versionA)
	if err != nil {
		return false, err
	}

	fileInfosB, err := driverB.DocumentVersionInfo(ctx, docID, versionB)
	if err != nil {
		return false, err
	}

	return reflect.DeepEqual(fileInfosA, fileInfosB), nil
}

// LatestDocumentVersionFileProvider returns a FileProvider for the files
// of the latest version of a document using the global connection.
func LatestDocumentVersionFileProvider(ctx context.Context, docID uu.ID) (p FileProvider, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	version, err := globalConn.LatestDocumentVersion(ctx, docID)
	if err != nil {
		return nil, err
	}

	return globalConn.DocumentVersionFileProvider(ctx, docID, version)
}

// FirstDocumentVersionCommitUserID returns the user ID that committed
// the first version of a document using the global connection.
func FirstDocumentVersionCommitUserID(ctx context.Context, docID uu.ID) (userID uu.ID, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	versions, err := globalConn.DocumentVersions(ctx, docID)
	if err != nil {
		return uu.IDNil, err
	}
	if len(versions) == 0 {
		// Should not happen if globalConn is implemented correctly,
		// but just in case, return a not found error instead of an index out of range panic.
		return uu.IDNil, NewErrDocumentNotFound(docID)
	}
	versionInfo, err := globalConn.DocumentVersionInfo(ctx, docID, versions[0])
	if err != nil {
		return uu.IDNil, err
	}
	return versionInfo.CommitUserID, nil
}

// CheckConnDocumentVersionFiles verifies that a document version in conn
// has exactly the expected files with matching content.
func CheckConnDocumentVersionFiles(ctx context.Context, conn Conn, docID uu.ID, version VersionTime, expectedFiles []fs.FileReader) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, conn, docID, version, expectedFiles)

	info, err := conn.DocumentVersionInfo(ctx, docID, version)
	if err != nil {
		return err
	}
	if len(info.Files) != len(expectedFiles) {
		return errs.Errorf("document %s version %s has %d files, expected %d", docID, version, len(info.Files), len(expectedFiles))
	}
	provider, err := conn.DocumentVersionFileProvider(ctx, docID, version)
	if err != nil {
		return err
	}

	for _, expectedFile := range expectedFiles {
		hasFile, err := provider.HasFile(expectedFile.Name())
		if err != nil {
			return err
		}
		if !hasFile {
			return errs.Errorf("document %s version %s is missing file %s", docID, version, expectedFile.Name())
		}
		expectedData, err := expectedFile.ReadAll()
		if err != nil {
			return err
		}
		data, err := provider.ReadFile(ctx, expectedFile.Name())
		if err != nil {
			return err
		}
		if !bytes.Equal(data, expectedData) {
			return errs.Errorf("document %s version %s file %s content not as expected", docID, version, expectedFile.Name())
		}
	}

	return nil
}
