package docdb

import (
	"context"
	"errors"

	"github.com/ungerik/go-fs"
	"github.com/ungerik/go-fs/uuiddir"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

// DocumentExists returns true if a document with the passed docID exists
func DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return conn.DocumentExists(ctx, docID)
}

// EnumDocumentIDs calls the passed callback with the ID of every document in the database
func EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx)

	return conn.EnumDocumentIDs(ctx, callback)
}

// EnumCompanyDocumentIDs calls the passed callback with the ID of every document of a company in the database
func EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID)

	return conn.EnumCompanyDocumentIDs(ctx, companyID, callback)
}

// DocumentCompanyID returns the companyID for a docID
func DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return conn.DocumentCompanyID(ctx, docID)
}

// SetDocumentCompanyID changes the companyID for a document
func SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, companyID)

	return conn.SetDocumentCompanyID(ctx, docID, companyID)
}

// DocumentVersions returns all version timestamps of a document in ascending order.
// Returns nil and no error if the document does not exist or has no versions.
func DocumentVersions(ctx context.Context, docID uu.ID) (versions []VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return conn.DocumentVersions(ctx, docID)
}

// LatestDocumentVersion returns the lates VersionTime of a document
func LatestDocumentVersion(ctx context.Context, docID uu.ID) (version VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return conn.LatestDocumentVersion(ctx, docID)
}

// DocumentVersionInfo returns the VersionInfo for a VersionTime
func DocumentVersionInfo(ctx context.Context, docID uu.ID, version VersionTime) (info *VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	return conn.DocumentVersionInfo(ctx, docID, version)
}

// LatestDocumentVersionInfo returns the VersionInfo for the latest document version
func LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (info *VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return conn.LatestDocumentVersionInfo(ctx, docID)
}

// DocumentVersionFileProvider returns a FileProvider for the files of a document version
func DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version VersionTime) (p FileProvider, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	return conn.DocumentVersionFileProvider(ctx, docID, version)
}

// ReadDocumentFile reads a file of the latest document version
func ReadDocumentFile(ctx context.Context, docID uu.ID, filename string) (data []byte, versionInfo *VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, filename)

	versionInfo, err = conn.LatestDocumentVersionInfo(ctx, docID)
	if err != nil {
		return nil, nil, err
	}
	data, err = conn.ReadDocumentVersionFile(ctx, docID, versionInfo.Version, filename)
	if err != nil {
		return nil, nil, err
	}
	return data, versionInfo, nil
}

// SubstituteDeletedDocumentVersion will substitue the passed version with
// the next existing version it does not exist anymore.
// Will return ErrDocumentHasNoCommitedVersion if there is no
// other commited version for the document.
func SubstituteDeletedDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) (validVersion VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	_, err = conn.DocumentVersionInfo(ctx, docID, version)
	if err == nil {
		return version, nil
	}

	if !errs.Has[ErrDocumentVersionNotFound](err) {
		return VersionTime{}, err
	}

	versions, err := conn.DocumentVersions(ctx, docID)
	if err != nil {
		return VersionTime{}, err
	}
	if len(versions) == 0 {
		return VersionTime{}, NewErrDocumentHasNoCommitedVersion(docID)
	}

	for i := range versions {
		// Return the first version after the deleted one
		if versions[i].Time.After(version.Time) {
			return versions[i], nil
		}
	}
	// Return latest vesion if none is after the deleted one
	return versions[len(versions)-1], nil
}

// ReadDocumentVersionFile returns the contents of a file of a document version.
// Wrapped ErrDocumentNotFound, ErrDocumentVersionNotFound, ErrDocumentFileNotFound
// will be returned in case of such error conditions.
func ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version VersionTime, filename string) (data []byte, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version, filename)

	return conn.ReadDocumentVersionFile(ctx, docID, version, filename)
}

func ReadLatestDocumentVersionFile(ctx context.Context, docID uu.ID, filename string) (data []byte, version VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version, filename)

	version, err = conn.LatestDocumentVersion(ctx, docID)
	if err != nil {
		return nil, VersionTime{}, err
	}
	data, err = conn.ReadDocumentVersionFile(ctx, docID, version, filename)
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

	data, err := conn.ReadDocumentVersionFile(ctx, docID, version, filename)
	if err != nil {
		return nil, err
	}
	return fs.NewMemFile(filename, data), nil
}

// DocumentFileReader returns a fs.FileReader for a file of the latest document version.
// Wrapped ErrDocumentNotFound, ErrDocumentHasNoCommitedVersion, ErrDocumentFileNotFound
// will be returned in case of such error conditions.
func DocumentFileReader(ctx context.Context, docID uu.ID, filename string) (fileReader fs.FileReader, versionInfo *VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, filename)

	versionInfo, err = conn.LatestDocumentVersionInfo(ctx, docID)
	if err != nil {
		return nil, nil, err
	}
	data, err := conn.ReadDocumentVersionFile(ctx, docID, versionInfo.Version, filename)
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

// DocumentCheckOutStatus returns the CheckOutStatus of a document.
// If the document is not checked out, then a nil CheckOutStatus will be returned.
// The methods Valid() and String() can be called on a nil CheckOutStatus.
// ErrDocumentNotFound is returned if the document does not exist.
func DocumentCheckOutStatus(ctx context.Context, docID uu.ID) (status *CheckOutStatus, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return conn.DocumentCheckOutStatus(ctx, docID)
}

// CheckedOutDocumentDir returns a fs.File for the directory
// where a document would be checked out.
func CheckedOutDocumentDir(docID uu.ID) fs.File {
	return conn.CheckedOutDocumentDir(docID)
}

// CheckedOutDocumentFileProvider returns a FileProvider for the directory
// where a document would be checked out.
func CheckedOutDocumentFileProvider(docID uu.ID) (p FileProvider, err error) {
	defer errs.WrapWithFuncParams(&err, docID)

	checkOutDir := conn.CheckedOutDocumentDir(docID)
	if !checkOutDir.Exists() {
		return nil, NewErrDocumentNotCheckedOut(docID)
	}
	return DirFileProvider(checkOutDir), nil
}

// CancelCheckOutDocument cancels a potential checkout.
// No error is returned if the document was not checked out.
// If the checkout was created by CheckOutNewDocument,
// then the new document is deleted without leaving any history
// and the returned lastVersion.IsNull() is true.
func CancelCheckOutDocument(ctx context.Context, docID uu.ID) (wasCheckedOut bool, lastVersion VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return conn.CancelCheckOutDocument(ctx, docID)
}

// CheckInDocument checks in a checked out document
// and returns the VersionInfo for the newly created version.
func CheckInDocument(ctx context.Context, docID uu.ID) (v *VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return conn.CheckInDocument(ctx, docID)
}

// CheckedOutDocuments returns the CheckOutStatus of all checked out documents.
func CheckedOutDocuments(ctx context.Context) (stati []*CheckOutStatus, err error) {
	defer errs.WrapWithFuncParams(&err, ctx)

	return conn.CheckedOutDocuments(ctx)
}

// CheckOutNewDocument creates a new document for a company in checked out state.
func CheckOutNewDocument(ctx context.Context, docID, companyID, userID uu.ID, reason string) (status *CheckOutStatus, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, companyID, userID, reason)

	return conn.CheckOutNewDocument(ctx, docID, companyID, userID, reason)
}

// CheckOutDocument checks out a document for a user with a stated reason.
// Returns ErrDocumentCheckedOut if the document is already checked out.
func CheckOutDocument(ctx context.Context, docID, userID uu.ID, reason string) (status *CheckOutStatus, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, userID, reason)

	return conn.CheckOutDocument(ctx, docID, userID, reason)
}

// DeleteDocument deletes all versions of a document
// including its workspace directory if checked out.
func DeleteDocument(ctx context.Context, docID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	return conn.DeleteDocument(ctx, docID)
}

// DeleteDocumentVersion deletes a version of a document that must not be checked out
// and returns the left over versions.
// If the version is the only version of the document,
// then the document will be deleted and no leftVersions are returned.
// Returns wrapped ErrDocumentNotFound, ErrDocumentVersionNotFound, ErrDocumentCheckedOut
// in case of such error conditions.
// DeleteDocumentVersion should not be used for normal docdb operations,
// just to clean up mistakes or sync database states.
func DeleteDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) (leftVersions []VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	return conn.DeleteDocumentVersion(ctx, docID, version)
}

// InsertDocumentVersion inserts a new version for an existing document.
// Returns wrapped ErrDocumentNotFound, ErrDocumentVersionAlreadyExists
// in case of such error conditions.
// InsertDocumentVersion should not be used for normal docdb operations,
// just to clean up mistakes or sync database states.
// func InsertDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime, userID uu.ID, reason string, files []fs.FileReader) (info *VersionInfo, err error) {
// 	defer errs.WrapWithFuncParams(&err, ctx, docID, version, userID, reason, files)

// 	return conn.InsertDocumentVersion(ctx, docID, version, userID, reason, files)
// }

func CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, files []fs.FileReader) (versionInfo *VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID, docID, userID, reason, files)

	return conn.CreateDocument(ctx, companyID, docID, userID, reason, files)
}

// AddDocumentVersion adds a new version to a document
// using the files returned by createVersion.
// Returns a wrapped ErrNoChanges if the files returned by
// createVersion are the same as the latest version.
func AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, userID, reason)

	return conn.AddDocumentVersion(ctx, docID, userID, reason, createVersion, onNewVersion)
}

// CopyDocumentFiles copies the files of all versions of
// a document to a backup directory.
//
// The backupDir must exist and a directory structure for the docID
// will be created inside the backupDir and returned as docDir.
//
// If true is passed for overwrite then existing files will be overwritten
// else an error is reeturned when docDir already exists.
//
// In case of an error the already created directories and files will be removed.
func CopyDocumentFiles(ctx context.Context, conn Conn, docID uu.ID, backupDir fs.File, overwrite bool) (docDir fs.File, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, backupDir, overwrite)

	docDir = uuiddir.Join(backupDir, docID)
	if !overwrite && docDir.Exists() {
		return "", errs.Errorf("document directory for backup already exists: %s", docDir)
	}
	defer func() {
		if err != nil {
			// Remove created files and directories in case of an error
			err = errors.Join(uuiddir.RemoveDir(backupDir, docDir))
		}
	}()

	log.InfoCtx(ctx, "Backing up document").
		UUID("docID", docID).
		Stringer("targetDir", docDir).
		Bool("overwrite", overwrite).
		Log()

	versions, err := conn.DocumentVersions(ctx, docID)
	if err != nil {
		return "", err
	}
	if len(versions) == 0 {
		return "", NewErrDocumentHasNoCommitedVersion(docID)
	}

	if !docDir.Exists() {
		log.Debug("Making directory").Stringer("dir", docDir).Log()
		err = docDir.MakeAllDirs()
		if err != nil {
			return "", err
		}
	}

	companyID, err := conn.DocumentCompanyID(ctx, docID)
	if err != nil {
		return "", err
	}
	companyIDFile := docDir.Join("company.id")
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
		versionInfoFile := docDir.Join(version.String() + ".json")
		log.Debug("Writing file").Stringer("file", versionInfoFile).Log()
		err = versionInfoFile.WriteJSON(ctx, versionInfo, "  ")
		if err != nil {
			return "", err
		}

		versionFileProvider, err := conn.DocumentVersionFileProvider(ctx, docID, version)
		if err != nil {
			return "", err
		}
		versionDir := docDir.Join(version.String())
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

	return docDir, nil
}

// CopyAllCompanyDocumentFiles copies the files of all versions of
// all documents of a company to a backup directory.
//
// The backupDir must exist and a directory structures for the documents
// will be created inside the backupDir and returned as docDirs.
// In case of an error the already backed up documents will be returned as docDirs.
//
// If true is passed for overwrite then existing files will be overwritten
// else an error is reeturned when docDir already exists.
func CopyAllCompanyDocumentFiles(ctx context.Context, conn Conn, companyID uu.ID, backupDir fs.File, overwrite bool) (docDirs []fs.File, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID, backupDir, overwrite)

	err = conn.EnumCompanyDocumentIDs(ctx, companyID, func(ctx context.Context, docID uu.ID) error {
		docDir, err := CopyDocumentFiles(ctx, conn, docID, backupDir, overwrite)
		if err != nil {
			return err
		}
		docDirs = append(docDirs, docDir)
		return nil
	})
	return docDirs, err
}
