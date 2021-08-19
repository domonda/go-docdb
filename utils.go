package docdb

import (
	"context"
	"reflect"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

// func HasChangedCheckedOutFiles(docID uu.ID) (changed bool, err error) {
// 	defer errs.WrapWithFuncParams(&err, docID)

// 	status, err := DocumentCheckOutStatus(docID)
// 	if err != nil {
// 		return false, err
// 	}
// 	if status == nil {
// 		return false, ErrDocumentNotCheckedOut(docID)
// 	}
// 	checkedOutDir := CheckedOutDocumentDir(docID)

// 	version, err := LatestDocumentVersion(docID)
// 	if err != nil {
// 		return false, err
// 	}
// 	checkedInFiles, err := DocumentVersionInfo(docID, version)
// 	if err != nil {
// 		return false, err
// 	}

// 	checkedInFileNames := make(map[string]struct{}, len(checkedInFiles))

// 	for _, checkedIn := range checkedInFiles {
// 		checkedOut, err := checkedOutDir.Join(checkedIn.Name).StatWithContentHash()
// 		if err != nil {
// 			return false, err
// 		}
// 		if !checkedOut.Exists || checkedOut.IsDir || checkedOut.Size != checkedIn.Size || checkedOut.ContentHash != checkedIn.Hash {
// 			return true, nil
// 		}
// 		checkedInFileNames[checkedIn.Name] = struct{}{}
// 	}

// 	errExtraFile := errors.New("errExtraFile")
// 	err = checkedOutDir.ListDir(func(file fs.File) error {
// 		if _, isCheckIn := checkedInFileNames[file.Name()]; !isCheckIn {
// 			return errExtraFile
// 		}
// 		return nil
// 	})
// 	if err == errExtraFile {
// 		return true, nil
// 	}
// 	if err != nil {
// 		return false, err
// 	}

// 	return false, nil
// }

func IdenticalDocumentVersionsOfDrivers(ctx context.Context, docID uu.ID, driverA Conn, versionA VersionTime, driverB Conn, versionB VersionTime) (identical bool, err error) {
	defer errs.WrapWithFuncParams(&err, docID, driverA, versionA, driverB, versionB)

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

func LatestDocumentVersionFileProvider(ctx context.Context, docID uu.ID) (p FileProvider, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	version, err := conn.LatestDocumentVersion(ctx, docID)
	if err != nil {
		return nil, err
	}

	return conn.DocumentVersionFileProvider(ctx, docID, version)
}

func FirstDocumentVersionCommitUserID(ctx context.Context, docID uu.ID) (userID uu.ID, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	versions, err := conn.DocumentVersions(ctx, docID)
	if err != nil {
		return uu.IDNil, err
	}
	if len(versions) == 0 {
		return uu.IDNil, NewErrDocumentHasNoCommitedVersion(docID)
	}
	versionInfo, err := conn.DocumentVersionInfo(ctx, docID, versions[0])
	if err != nil {
		return uu.IDNil, err
	}
	return versionInfo.CommitUserID, nil
}
