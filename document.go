package docdb

import (
	"context"
	"errors"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
	"github.com/ungerik/go-fs/uuiddir"
)

type Version struct {
	*VersionInfo

	FileContents map[string][]byte
}

type Document struct {
	ID        uu.ID
	CompanyID uu.ID
	Versions  []Version
}

func ReadDocument(ctx context.Context, conn Conn, docID uu.ID) (doc *Document, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, conn, docID)

	doc = &Document{ID: docID}
	doc.CompanyID, err = conn.DocumentCompanyID(ctx, docID)
	if err != nil {
		return nil, err
	}

	versionInfos, err := conn.DocumentVersions(ctx, docID)
	if err != nil {
		return nil, err
	}

	doc.Versions = make([]Version, len(versionInfos))
	for i, version := range versionInfos {
		versionInfo, err := conn.DocumentVersionInfo(ctx, docID, version)
		if err != nil {
			return nil, err
		}
		doc.Versions[i].VersionInfo = versionInfo
		doc.Versions[i].FileContents = make(map[string][]byte)

		versionFileProvider, err := conn.DocumentVersionFileProvider(ctx, docID, version)
		if err != nil {
			return nil, err
		}
		filenames, err := versionFileProvider.ListFiles(ctx)
		if err != nil {
			return nil, err
		}
		for _, filename := range filenames {
			data, err := versionFileProvider.ReadFile(ctx, filename)
			if err != nil {
				return nil, err
			}
			if int64(len(data)) != versionInfo.Files[filename].Size {
				return nil, errs.Errorf("document %s version %s file %q has %d bytes, but expected %d bytes according to version info", docID, version, filename, len(data), versionInfo.Files[filename].Size)
			}
			if hash := ContentHash(data); hash != versionInfo.Files[filename].Hash {
				return nil, errs.Errorf("document %s version %s file %q has hash %s, but expected %s according to version info", docID, version, filename, hash, versionInfo.Files[filename].Hash)
			}
			doc.Versions[i].FileContents[filename] = data
		}
	}

	return doc, nil
}

// BackupDocument copies the files of all versions of
// a document to a backup directory.
//
// The backupDir must exist and a directory structure for the docID
// will be created inside the backupDir and returned as docDir.
//
// If true is passed for overwrite then existing files will be overwritten
// else an error is reeturned when docDir already exists.
//
// In case of an error the already created directories and files will be removed.
func BackupDocument(ctx context.Context, conn Conn, docID uu.ID, backupDir fs.File, overwrite bool) (docDir fs.File, err error) {
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

// BackupAllCompanyDocuments copies the files of all versions of
// all documents of a company to a backup directory.
//
// The backupDir must exist and a directory structures for the documents
// will be created inside the backupDir and returned as docDirs.
// In case of an error the already backed up documents will be returned as docDirs.
//
// If true is passed for overwrite then existing files will be overwritten
// else an error is reeturned when docDir already exists.
func BackupAllCompanyDocuments(ctx context.Context, conn Conn, companyID uu.ID, backupDir fs.File, overwrite bool) (docDirs []fs.File, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID, backupDir, overwrite)

	err = conn.EnumCompanyDocumentIDs(ctx, companyID, func(ctx context.Context, docID uu.ID) error {
		docDir, err := BackupDocument(ctx, conn, docID, backupDir, overwrite)
		if err != nil {
			return err
		}
		docDirs = append(docDirs, docDir)
		return nil
	})
	return docDirs, err
}
