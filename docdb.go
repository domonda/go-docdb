package docdb

import (
	"context"
	"errors"
	"fmt"

	"github.com/ungerik/go-fs"
	"github.com/ungerik/go-fs/uuiddir"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

// DocumentExists returns true if a document with the passed docID exists
func DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return GetConn().DocumentExists(ctx, docID)
}

// CompanyIDs returns the IDs of all companies that have documents,
// sorted by ID for a consistent order.
func CompanyIDs(ctx context.Context) (companyIDs uu.IDSlice, err error) {
	defer errs.WrapWithFuncParams(&err, ctx)

	return GetConn().CompanyIDs(ctx)
}

// CompanyDocumentIDs returns the IDs of all documents of a company,
// sorted by ID for a consistent order.
func CompanyDocumentIDs(ctx context.Context, companyID uu.ID) (docIDs uu.IDSlice, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID)

	return GetConn().CompanyDocumentIDs(ctx, companyID)
}

// DocumentCompanyID returns the companyID for a docID
func DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return GetConn().DocumentCompanyID(ctx, docID)
}

// SetDocumentCompanyID changes the companyID for a document
func SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, companyID)

	return GetConn().SetDocumentCompanyID(ctx, docID, companyID)
}

// DocumentVersions returns all version timestamps of a document in ascending order.
// Returns ErrDocumentNotFound if the document does not exist.
func DocumentVersions(ctx context.Context, docID uu.ID) (versions []VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return GetConn().DocumentVersions(ctx, docID)
}

// LatestDocumentVersion returns the latest VersionTime of a document
func LatestDocumentVersion(ctx context.Context, docID uu.ID) (version VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return GetConn().LatestDocumentVersion(ctx, docID)
}

// DocumentVersionInfo returns the VersionInfo for a VersionTime
func DocumentVersionInfo(ctx context.Context, docID uu.ID, version VersionTime) (info *VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	return GetConn().DocumentVersionInfo(ctx, docID, version)
}

// LatestDocumentVersionInfo returns the VersionInfo for the latest document version
func LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (info *VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return GetConn().LatestDocumentVersionInfo(ctx, docID)
}

// DocumentVersionFileProvider returns a FileProvider for the files of a document version
func DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version VersionTime) (p FileProvider, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	return GetConn().DocumentVersionFileProvider(ctx, docID, version)
}

// ReadDocumentFile reads a file of the latest document version
func ReadDocumentFile(ctx context.Context, docID uu.ID, filename string) (data []byte, versionInfo *VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, filename)

	versionInfo, err = GetConn().LatestDocumentVersionInfo(ctx, docID)
	if err != nil {
		return nil, nil, err
	}
	data, err = GetConn().ReadDocumentVersionFile(ctx, docID, versionInfo.Version, filename)
	if err != nil {
		return nil, nil, err
	}
	return data, versionInfo, nil
}

// SubstituteDeletedDocumentVersion will substitute the passed version with
// the next existing version if it does not exist anymore.
// Will return ErrDocumentNotFound if there is no
// other version for the document.
func SubstituteDeletedDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) (validVersion VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	_, err = GetConn().DocumentVersionInfo(ctx, docID, version)
	if err == nil {
		return version, nil
	}

	if !errs.Has[ErrDocumentVersionNotFound](err) {
		return VersionTime{}, err
	}

	versions, err := GetConn().DocumentVersions(ctx, docID)
	if err != nil {
		return VersionTime{}, err
	}
	if len(versions) == 0 {
		return VersionTime{}, NewErrDocumentNotFound(docID)
	}

	for i := range versions {
		// Return the first version after the deleted one
		if versions[i].Time.After(version.Time) {
			return versions[i], nil
		}
	}
	// Return latest version if none is after the deleted one
	return versions[len(versions)-1], nil
}

// ReadDocumentVersionFile returns the contents of a file of a document version.
// Wrapped ErrDocumentNotFound, ErrDocumentVersionNotFound, ErrDocumentFileNotFound
// will be returned in case of such error conditions.
func ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version VersionTime, filename string) (data []byte, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version, filename)

	return GetConn().ReadDocumentVersionFile(ctx, docID, version, filename)
}

// ReadLatestDocumentVersionFile reads a file from the latest version of a document
// and returns the file data along with the version timestamp.
func ReadLatestDocumentVersionFile(ctx context.Context, docID uu.ID, filename string) (data []byte, version VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, filename)

	version, err = GetConn().LatestDocumentVersion(ctx, docID)
	if err != nil {
		return nil, VersionTime{}, err
	}
	data, err = GetConn().ReadDocumentVersionFile(ctx, docID, version, filename)
	if err != nil {
		return nil, VersionTime{}, err
	}
	return data, version, nil
}

// DocumentVersionFileReader returns a fs.FileReader for a file of a document version.
// Wrapped ErrDocumentNotFound, ErrDocumentVersionNotFound, ErrDocumentFileNotFound
// will be returned in case of such error conditions.
func DocumentVersionFileReader(ctx context.Context, docID uu.ID, version VersionTime, filename string) (fileReader fs.FileReader, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version, filename)

	data, err := GetConn().ReadDocumentVersionFile(ctx, docID, version, filename)
	if err != nil {
		return nil, err
	}
	return fs.NewMemFile(filename, data), nil
}

// DocumentFileReader returns a fs.FileReader for a file of the latest document version.
// Wrapped ErrDocumentNotFound, ErrDocumentFileNotFound
// will be returned in case of such error conditions.
func DocumentFileReader(ctx context.Context, docID uu.ID, filename string) (fileReader fs.FileReader, versionInfo *VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, filename)

	versionInfo, err = GetConn().LatestDocumentVersionInfo(ctx, docID)
	if err != nil {
		return nil, nil, err
	}
	data, err := GetConn().ReadDocumentVersionFile(ctx, docID, versionInfo.Version, filename)
	if err != nil {
		return nil, nil, err
	}
	return fs.NewMemFile(filename, data), versionInfo, nil
}

// DocumentFileExists returns if a document file with filename exists in the latest document version.
func DocumentFileExists(ctx context.Context, docID uu.ID, filename string) (exists bool, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, filename)

	file, _, err := DocumentFileReader(ctx, docID, filename)
	if errs.Has[ErrDocumentFileNotFound](err) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return file.Exists(), nil
}

// DeleteDocument deletes all versions and stored files of a document.
// Returns wrapped ErrDocumentNotFound in case the document does not exist.
func DeleteDocument(ctx context.Context, docID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return GetConn().DeleteDocument(ctx, docID)
}

// DeleteDocumentVersion deletes a version of a document
// and returns the left over versions.
// If the version is the only version of the document,
// then the document will be deleted and no leftVersions are returned.
// Returns wrapped ErrDocumentNotFound and ErrDocumentVersionNotFound
// in case of such error conditions.
// DeleteDocumentVersion should not be used for normal docdb operations,
// just to clean up mistakes or sync database states.
func DeleteDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) (leftVersions []VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	return GetConn().DeleteDocumentVersion(ctx, docID, version)
}

// CreateDocument creates a new document with the provided files.
// The document is created with companyID, docID, and userID as metadata,
// and reason describes why the document is being created.
//
// After the document version is created but before it is committed,
// the onNewVersion callback is called with the resulting VersionInfo.
// If onNewVersion returns an error or panics, the entire document creation
// is atomically rolled back, the error is returned, or the panic is propagated.
//
// At least one file must be provided: a document's first version cannot be
// empty, so an empty files slice is rejected with an error.
//
// Returns ErrDocumentAlreadyExists if a document with docID already exists.
func CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, version VersionTime, files []fs.FileReader, onNewVersion OnNewVersionFunc) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID, docID, userID, reason, version, files, onNewVersion)

	return GetConn().CreateDocument(ctx, companyID, docID, userID, reason, version, files, onNewVersion)
}

// AddDocumentVersion adds a new version to an existing document.
// The createVersion callback is invoked with the previous version info
// and should return the files to write, files to remove, and optionally
// a new company ID for the document.
//
// After the new version is created but before it is committed,
// the onNewVersion callback is called with the resulting VersionInfo.
// If createVersion or onNewVersion returns an error or panics,
// the entire version creation is atomically rolled back,
// the error is returned, or the panic is propagated.
//
// A new version must keep at least one file: removing all files of a document
// is rejected with an error (use DeleteDocument to remove the document entirely).
//
// Returns wrapped ErrDocumentNotFound if the document does not exist.
// Returns wrapped ErrNoChanges if the new version has identical files
// compared to the previous version.
func AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, userID, reason, createVersion, onNewVersion)

	return GetConn().AddDocumentVersion(ctx, docID, userID, reason, createVersion, onNewVersion)
}

// AddMultiDocumentVersion adds a new version to multiple existing documents as atomic operation.
// See AddDocumentVersion for details on the callbacks and error handling.
func AddMultiDocumentVersion(ctx context.Context, docIDs uu.IDSlice, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docIDs, userID, reason, createVersion, onNewVersion)

	return GetConn().AddMultiDocumentVersion(ctx, docIDs, userID, reason, createVersion, onNewVersion)
}

// CopyDocumentFiles copies the files of all versions of
// a document to a backup directory.
//
// The backupDir must exist and a directory structure for the docID
// will be created inside the backupDir and returned as docDir.
//
// If true is passed for overwrite then existing files will be overwritten
// else an error is returned when docDir already exists.
//
// In case of an error the already created directories and files will be removed.
func CopyDocumentFiles(ctx context.Context, conn Conn, docID uu.ID, backupDir fs.File, overwrite bool) (destDocDir fs.File, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, backupDir, overwrite)

	destDocDir = uuiddir.Join(backupDir, docID)
	if !overwrite && destDocDir.Exists() {
		return "", errs.Errorf("document directory for backup already exists: %s", destDocDir)
	}
	// Better not do that because there might be existing files from before that should not get deleted:
	// defer func() {
	// 	if err != nil {
	// 		// Remove created files and directories in case of an error
	// 		err = errors.Join(err, uuiddir.RemoveDir(backupDir, docDir))
	// 	}
	// }()

	log.InfoCtx(ctx, "Backing up document").
		UUID("docID", docID).
		Stringer("destDocDir", destDocDir).
		Bool("overwrite", overwrite).
		Log()

	versions, err := conn.DocumentVersions(ctx, docID)
	if err != nil {
		return "", err
	}
	if len(versions) == 0 {
		return "", NewErrDocumentNotFound(docID)
	}

	if !destDocDir.Exists() {
		log.Debug("Making directory").Stringer("dir", destDocDir).Log()
		err = destDocDir.MakeAllDirs()
		if err != nil {
			return "", err
		}
	}

	companyID, err := conn.DocumentCompanyID(ctx, docID)
	if err != nil {
		return "", err
	}
	companyIDFile := destDocDir.Join("company.id")
	log.Debug("Writing file").Stringer("file", companyIDFile).Log()
	err = companyIDFile.WriteAllString(companyID.String())
	if err != nil {
		return "", err
	}

	for _, version := range versions {
		versionInfo, err := conn.DocumentVersionInfo(ctx, docID, version)
		if err != nil {
			return "", err
		}
		versionInfoFile := destDocDir.Join(version.String() + ".json")
		log.Debug("Writing file").Stringer("file", versionInfoFile).Log()
		err = versionInfoFile.WriteJSON(ctx, versionInfo, "  ")
		if err != nil {
			return "", err
		}

		versionFileProvider, err := conn.DocumentVersionFileProvider(ctx, docID, version)
		if err != nil {
			return "", err
		}
		versionDir := destDocDir.Join(version.String())
		log.Debug("Making directory").Stringer("dir", versionDir).Log()
		err = versionDir.MakeDir()
		if err != nil {
			return "", err
		}
		filenames, err := versionFileProvider.ListFiles(ctx)
		if err != nil {
			return "", err
		}
		for _, filename := range filenames {
			data, err := versionFileProvider.ReadFile(ctx, filename)
			if err != nil {
				return "", err
			}
			file := versionDir.Join(filename)
			log.Debug("Writing file").Stringer("file", file).Log()
			err = file.WriteAllContext(ctx, data)
			if err != nil {
				return "", err
			}
		}
	}

	return destDocDir, nil
}

// CopyAllCompanyDocumentFiles copies the files of all versions of
// all documents of a company to a backup directory.
//
// The backupDir must exist and a directory structures for the documents
// will be created inside the backupDir and returned as docDirs.
// In case of an error the already backed up documents will be returned as docDirs.
//
// If true is passed for overwrite then existing files will be overwritten
// else an error is returned when docDir already exists.
//
// If onProgress is not nil it is called before copying each document with the
// document's zero-based index and the total number of documents to copy.
func CopyAllCompanyDocumentFiles(ctx context.Context, conn Conn, companyID uu.ID, backupDir fs.File, overwrite bool, onProgress DocProgressCallback) (docDirs []fs.File, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID, backupDir, overwrite, onProgress)

	docIDs, err := conn.CompanyDocumentIDs(ctx, companyID)
	if err != nil {
		return docDirs, err
	}
	total := len(docIDs)
	for index, docID := range docIDs {
		if onProgress != nil {
			onProgress(ctx, docID, index, total)
		}
		docDir, err := CopyDocumentFiles(ctx, conn, docID, backupDir, overwrite)
		if err != nil {
			return docDirs, err
		}
		docDirs = append(docDirs, docDir)
	}
	return docDirs, nil
}

// AddMultiDocumentVersionImpl adds a new version to each document in docIDs
// by calling conn.AddDocumentVersion for each one sequentially.
//
// It is the shared implementation for Conn.AddMultiDocumentVersion.
// Conn implementations that can't provide native multi-document atomicity
// should delegate to this function.
//
// Documents with no file changes (ErrNoChanges from AddDocumentVersion) are skipped.
// Returns ErrNoChanges only if no document was changed at all.
//
// Atomicity is achieved by tracking each successfully created version and,
// on any error, rolling back all of them via conn.DeleteDocumentVersion.
// Any rollback errors are joined to the returned error.
func AddMultiDocumentVersionImpl(ctx context.Context, conn Conn, docIDs uu.IDSlice, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docIDs, userID, reason, createVersion, onNewVersion)

	type createdVersion struct {
		docID   uu.ID
		version VersionTime
	}
	var created []createdVersion

	defer func() {
		if r := recover(); r != nil {
			err = errs.AsErrorWithDebugStack(r)
		}
		if err != nil {
			for _, cv := range created {
				_, deleteErr := conn.DeleteDocumentVersion(ctx, cv.docID, cv.version)
				if deleteErr != nil {
					err = errors.Join(err,
						fmt.Errorf("failed to undo new document version of atomic multi-document operation: %w", deleteErr),
					)
				}
			}
		}
	}()

	for _, docID := range docIDs {
		err = conn.AddDocumentVersion(ctx, docID, userID, reason, createVersion, func(ctx context.Context, versionInfo *VersionInfo) error {
			cbErr := onNewVersion(ctx, versionInfo)
			if cbErr == nil {
				created = append(created, createdVersion{
					docID:   versionInfo.DocID,
					version: versionInfo.Version,
				})
			}
			return cbErr
		})
		if err != nil {
			// Skip documents that have no changes,
			// only return ErrNoChanges if no document was changed at all.
			if errors.Is(err, ErrNoChanges) {
				continue
			}
			return err
		}
	}
	if len(created) == 0 {
		return ErrNoChanges
	}
	return nil
}
