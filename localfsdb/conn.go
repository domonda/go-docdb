package localfsdb

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sort"
	"testing"
	"time"

	"github.com/ungerik/go-fs"
	"github.com/ungerik/go-fs/uuiddir"
	"golang.org/x/exp/slices"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

// Compiler check if *Conn implements docdb.Conn
var _ docdb.Conn = (*Conn)(nil)

type Conn struct {
	documentsDir fs.File
	workspaceDir fs.File
	companiesDir fs.File
}

func NewConn(documentsDir, workspaceDir, companiesDir fs.File) *Conn {
	if !documentsDir.IsDir() {
		panic("documentsDir does not exist: '" + string(documentsDir) + "'")
	}
	if documentsDir.FileSystem() != fs.Local {
		panic("documentsDir is not on local file-system: '" + string(documentsDir) + "'")
	}
	if !workspaceDir.IsDir() {
		panic("workspaceDir does not exist: '" + string(workspaceDir) + "'")
	}
	if workspaceDir.FileSystem() != fs.Local {
		panic("workspaceDir is not on local file-system: '" + string(workspaceDir) + "'")
	}
	if !companiesDir.IsDir() {
		panic("companiesDir does not exist: '" + string(companiesDir) + "'")
	}
	if companiesDir.FileSystem() != fs.Local {
		panic("companiesDir is not on local file-system: '" + string(companiesDir) + "'")
	}
	return &Conn{
		documentsDir: documentsDir,
		workspaceDir: workspaceDir,
		companiesDir: companiesDir,
	}
}

// NewTestConn creates a new db in a temporary
// directory that will be cleaned up after the test.
func NewTestConn(t *testing.T) *Conn {
	t.Helper()

	dir, err := fs.MakeTempDir()
	if err != nil {
		t.Fatal(err)
	}

	t.Cleanup(func() {
		err := dir.RemoveDirContentsRecursive()
		if err != nil {
			t.Errorf("can't clean up docdb test-dir %s because of: %s", dir.Path(), err)
		}
	})

	documentsDir := dir.Join("documents")
	workspaceDir := dir.Join("workspace")
	companiesDir := dir.Join("companies")

	err = documentsDir.MakeDir()
	if err != nil {
		t.Fatal(err)
	}
	err = workspaceDir.MakeDir()
	if err != nil {
		t.Fatal(err)
	}
	err = companiesDir.MakeDir()
	if err != nil {
		t.Fatal(err)
	}

	return NewConn(
		documentsDir,
		workspaceDir,
		companiesDir,
	)
}

func (c *Conn) String() string {
	return fmt.Sprintf(
		"localfsdb.Conn{Documents: %q, Workspace: %q}",
		c.documentsDir.LocalPath(),
		c.workspaceDir.LocalPath(),
	)
}

func (c *Conn) documentDir(docID uu.ID) fs.File {
	return uuiddir.Join(c.documentsDir, docID)
}

func (c *Conn) documentAndVersionDir(docID uu.ID, version docdb.VersionTime) (docDir fs.File, versionDir fs.File, err error) {
	docDir = c.documentDir(docID)
	if !docDir.IsDir() {
		return docDir, "", docdb.NewErrDocumentNotFound(docID)
	}
	versionDir = docDir.Join(version.String())
	if !versionDir.IsDir() {
		return docDir, versionDir, docdb.NewErrDocumentVersionNotFound(docID, version)
	}
	return docDir, versionDir, nil
}

func (c *Conn) documentCheckOutStatusFile(docID uu.ID) fs.File {
	return c.documentDir(docID).Join("checkout-status.json")
}

func (c *Conn) companyDocumentDir(companyID, docID uu.ID) fs.File {
	companyDir := c.companiesDir.Join(companyID.String())
	return uuiddir.Join(companyDir, docID)
}

func (c *Conn) CheckedOutDocumentDir(docID uu.ID) fs.File {
	return c.workspaceDir.Join(docID.String())
}

func (c *Conn) DocumentExists(_ context.Context, docID uu.ID) (exists bool, err error) {
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	return c.documentDir(docID).IsDir(), nil
}

func (c *Conn) EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error {
	return uuiddir.Enum(ctx, c.documentsDir, func(docDir fs.File, id [16]byte) error {
		if docDir.IsEmptyDir() {
			log.Debugf("Empty document directory: %s", docDir.AbsPath()).Log()
			return nil
		}
		return callback(ctx, id)
	})
}

func (c *Conn) EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID)

	return uuiddir.Enum(
		ctx,
		c.companiesDir.Join(companyID.String()),
		func(docDir fs.File, id [16]byte) error {
			return callback(ctx, id)
		},
	)
}

func (c *Conn) makeCompanyDocumentDir(companyID, docID uu.ID) error {
	dir := c.companyDocumentDir(companyID, docID)
	// if !dir.Exists() {
	// 	log.Debugf("makeCompanyDocumentDir(%s, %s): %s", companyID, docID, dir.Path()).Log()
	// }
	return dir.MakeAllDirs()
}

func (c *Conn) removeCompanyDocumentDirIfExists(companyID, docID uu.ID) error {
	docDir := c.companyDocumentDir(companyID, docID)
	if !docDir.Exists() {
		return nil
	}
	companyDir := c.companiesDir.Join(companyID.String())
	return uuiddir.RemoveDir(companyDir, docDir)
}

func (c *Conn) latestDocumentVersionInfo(docID uu.ID) (versionInfo *docdb.VersionInfo, versionDir fs.File, err error) {
	defer errs.WrapWithFuncParams(&err, docID)

	docDir := c.documentDir(docID)
	if !docDir.IsDir() {
		return nil, "", docdb.NewErrDocumentNotFound(docID)
	}

	var latestVersion docdb.VersionTime
	err = docDir.ListDirInfo(func(dir fs.File, dirInfo fs.FileInfo) error {
		if !dirInfo.IsDir || dirInfo.IsHidden {
			return nil
		}
		version, err := docdb.VersionTimeFromString(dirInfo.Name)
		if err != nil {
			log.Error("Can't parse document sub-directory name as version, skipping version and continuing...").
				UUID("docID", docID).
				Str("dirName", dirInfo.Name).
				Str("dirPath", dir.Path()).
				Err(err).
				Log()
			return nil
		}
		infoFile := docDir.Join(version.String() + ".json")
		if !infoFile.Exists() {
			versionFiles, err := dir.ListDirMax(20)
			if err != nil {
				log.Error("Error listing document version directory").Err(err).Log()
			}
			log.Error("Document version directory has no corresponding version info JSON file, skipping version and continuing...").
				UUID("docID", docID).
				Str("jsonFile", infoFile.Name()).
				Str("versionDir", dirInfo.Name).
				Strs("versionFiles", fs.FilesToNames(versionFiles)).
				Str("docDir", docDir.Path()).
				Log()
			return nil
		}
		if version.Time.After(latestVersion.Time) {
			latestVersion = version
			versionDir = dir
		}
		return nil
	})
	if err != nil {
		return nil, "", err
	}

	if latestVersion.IsNull() {
		return nil, "", docdb.NewErrDocumentHasNoCommitedVersion(docID)
	}

	versionInfo, _, err = c.documentVersionInfo(docID, latestVersion)
	if err != nil {
		return nil, "", err
	}

	return versionInfo, versionDir, nil
}

func (c *Conn) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	if ctx.Err() != nil {
		return uu.IDNil, ctx.Err()
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	return c.documentCompanyID(docID)
}

func (c *Conn) documentCompanyID(docID uu.ID) (companyID uu.ID, err error) {
	defer errs.WrapWithFuncParams(&err, docID)

	file := c.documentDir(docID).Join("company.id")
	if file.Exists() {
		uuidStr, err := file.ReadAllString()
		if err != nil {
			return uu.IDNil, err
		}
		return uu.IDFromString(uuidStr)
	}

	// Backward compatible way, when no company.id file exists:
	version, versionDir, err := c.latestDocumentVersionInfo(docID)
	if err != nil {
		return uu.IDNil, err
	}
	var doc struct {
		CompanyID uu.ID `json:"companyId"`
	}
	err = versionDir.Join("doc.json").ReadJSON(context.Background(), &doc)
	if err != nil {
		return uu.IDNil, err
	}
	if doc.CompanyID.IsNil() {
		return uu.IDNil, errs.Errorf("document %s version %s/doc.json has no companyId", docID, version)
	}

	return doc.CompanyID, nil
}

func (c *Conn) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, companyID)

	if err = ctx.Err(); err != nil {
		return err
	}

	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	return c.setDocumentCompanyID(docID, companyID)
}

func (c *Conn) setDocumentCompanyID(docID, companyID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, docID, companyID)

	if err = companyID.Validate(); err != nil {
		return err
	}

	docDir := c.documentDir(docID)
	if !docDir.Exists() {
		return docdb.NewErrDocumentNotFound(docID)
	}

	currCompanyID, err := c.documentCompanyID(docID)
	if err != nil {
		return err
	}
	var (
		currCompanyDir               = c.companiesDir.Join(currCompanyID.String())
		currCompanyDocumentDir       = c.companyDocumentDir(currCompanyID, docID)
		currCompanyDocumentDirExists = currCompanyDocumentDir.Exists()
	)

	if currCompanyID == companyID {
		// Same company, make sure currCompanyDocumentDir exists and return
		if !currCompanyDocumentDirExists {
			return currCompanyDocumentDir.MakeAllDirs()
		}
		return nil
	}

	if currCompanyDocumentDirExists {
		err = uuiddir.RemoveDir(currCompanyDir, currCompanyDocumentDir)
		if err != nil {
			return err
		}
	}

	err = docDir.Join("company.id").WriteAllString(companyID.String())
	if err != nil {
		return err
	}
	return c.companyDocumentDir(companyID, docID).MakeAllDirs()
}

func (c *Conn) DocumentVersions(ctx context.Context, docID uu.ID) (versions []docdb.VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	return c.documentVersions(docID)
}

func (c *Conn) documentVersions(docID uu.ID) (versions []docdb.VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, docID)

	docDir := c.documentDir(docID)
	if !docDir.IsDir() {
		return nil, nil
	}
	err = docDir.ListDirInfo(func(dir fs.File, dirInfo fs.FileInfo) error {
		if !dirInfo.IsDir || dirInfo.IsHidden {
			return nil
		}
		version, err := docdb.VersionTimeFromString(dirInfo.Name)
		if err != nil {
			log.Error("Can't parse document sub-directory name as version, skipping version and continuing...").
				UUID("docID", docID).
				Str("dirName", dirInfo.Name).
				Str("dirPath", dir.Path()).
				Err(err).
				Log()
			return nil
		}
		infoFile := docDir.Join(version.String() + ".json")
		if !infoFile.Exists() {
			versionFiles, err := dir.ListDirMax(20)
			if err != nil {
				log.Error("Error listing document version directory").Err(err).Log()
			}
			log.Error("Document version directory has no corresponding version info JSON file, skipping version and continuing...").
				UUID("docID", docID).
				Str("jsonFile", infoFile.Name()).
				Str("versionDir", dirInfo.Name).
				Strs("versionFiles", fs.FilesToNames(versionFiles)).
				Str("docDir", docDir.Path()).
				Log()
			return nil
		}
		versions = append(versions, version)
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(versions, func(a, b int) bool { return versions[a].Before(versions[b]) })
	return versions, nil
}

func (c *Conn) documentVersionInfo(docID uu.ID, version docdb.VersionTime) (versionInfo *docdb.VersionInfo, docDir fs.File, err error) {
	defer errs.WrapWithFuncParams(&err, docID, version)

	if version.IsNull() {
		return nil, "", docdb.NewErrDocumentHasNoCommitedVersion(docID)
	}

	docDir = c.documentDir(docID)
	if !docDir.IsDir() {
		return nil, docDir, docdb.NewErrDocumentNotFound(docID)
	}

	infoFile := docDir.Join(version.String() + ".json")
	versionInfo, err = docdb.ReadVersionInfoJSON(infoFile, true)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			log.Warn("Document version JSON file not found").
				Err(err).
				UUID("docID", docID).
				Stringer("version", version).
				Str("filename", infoFile.Name()).
				Log()
			err = docdb.NewErrDocumentVersionNotFound(docID, version)
		}
		return nil, docDir, err
	}

	return versionInfo, docDir, nil
}

func (c *Conn) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (versionInfo *docdb.VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	versionInfo, _, err = c.documentVersionInfo(docID, version)
	if err != nil {
		return nil, err
	}

	return versionInfo, nil
}

func (c *Conn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (versionInfo *docdb.VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	versionInfo, _, err = c.latestDocumentVersionInfo(docID)
	return versionInfo, err
}

func (c *Conn) LatestDocumentVersion(ctx context.Context, docID uu.ID) (latest docdb.VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	info, err := c.LatestDocumentVersionInfo(ctx, docID)
	if err != nil {
		return docdb.VersionTime{}, err
	}
	return info.Version, nil
}

func (c *Conn) ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version docdb.VersionTime, filename string) (data []byte, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version, filename)

	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	_, versionDir, err := c.documentAndVersionDir(docID, version)
	if err != nil {
		return nil, err
	}
	file := versionDir.Join(filename)
	if !file.Exists() {
		return nil, docdb.NewErrDocumentFileNotFound(docID, filename)
	}
	return file.ReadAllContext(ctx)
}

func (c *Conn) DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version docdb.VersionTime) (p docdb.FileProvider, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	_, versionDir, err := c.documentAndVersionDir(docID, version)
	if err != nil {
		return nil, err
	}
	return docdb.DirFileProvider(versionDir), nil
}

func (c *Conn) DocumentCheckOutStatus(ctx context.Context, docID uu.ID) (status *docdb.CheckOutStatus, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	return c.documentCheckOutStatus(docID)
}

func (c *Conn) documentCheckOutStatus(docID uu.ID) (status *docdb.CheckOutStatus, err error) {
	defer errs.WrapWithFuncParams(&err, docID)

	statusFile := c.documentCheckOutStatusFile(docID)
	if !statusFile.Exists() {
		if !statusFile.Dir().Exists() {
			return nil, docdb.NewErrDocumentNotFound(docID)
		}
		return nil, nil
	}
	err = statusFile.ReadJSON(context.Background(), &status)
	if err != nil {
		return nil, err
	}
	return status, nil
}

func (c *Conn) writeDocumentCheckOutStatusFile(docID uu.ID, version docdb.VersionTime, userID uu.ID, reason string, checkOutDir fs.File) (status *docdb.CheckOutStatus, err error) {
	defer errs.WrapWithFuncParams(&err, docID, version, userID, reason, checkOutDir)

	status = &docdb.CheckOutStatus{
		// CompanyID:   companyID,
		DocID:       docID,
		Version:     version,
		UserID:      userID,
		Reason:      reason,
		Time:        time.Now().UTC(),
		CheckOutDir: checkOutDir,
	}
	err = c.documentCheckOutStatusFile(docID).WriteJSON(context.Background(), status, "  ")
	if err != nil {
		return nil, err
	}
	return status, nil
}

func (c *Conn) CheckOutNewDocument(ctx context.Context, docID, companyID, userID uu.ID, reason string) (status *docdb.CheckOutStatus, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, companyID, userID, reason)

	switch {
	case ctx.Err() != nil:
		return nil, ctx.Err()
	case !docID.Valid():
		return nil, errs.New("CheckOutNewDocument: invalid docID")
	case !companyID.Valid():
		return nil, errs.New("CheckOutNewDocument: invalid companyID")
	case !userID.Valid():
		return nil, errs.New("CheckOutNewDocument: invalid userID")
	case reason == "":
		return nil, errs.New("CheckOutNewDocument: reason must not be empty")
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	if c.documentDir(docID).Exists() {
		return nil, errs.Errorf("CheckOutNewDocument: document %s already exists", docID)
	}

	log.Info("CheckOutNewDocument").
		Ctx(ctx).
		UUID("docID", docID).
		UUID("companyID", companyID).
		UUID("userID", userID).
		Str("reason", reason).
		Log()

	docDir := c.documentDir(docID)
	checkOutDir := c.CheckedOutDocumentDir(docID)
	defer func() {
		if err != nil {
			if docDir.Exists() {
				e := uuiddir.RemoveDir(c.documentsDir, docDir)
				if e != nil {
					log.Error("delete docDir").Ctx(ctx).Err(e).Log()
				}
			}
			if checkOutDir.Exists() {
				e := checkOutDir.RemoveRecursive()
				if e != nil {
					log.Error("delete checkOutDir").Ctx(ctx).Err(e).Log()
				}
			}
			e := c.removeCompanyDocumentDirIfExists(companyID, docID)
			if e != nil {
				log.Error("removeCompanyDocumentDirIfExists").Ctx(ctx).Err(e).Log()
			}
		}
	}()

	err = docDir.MakeAllDirs()
	if err != nil {
		return nil, err
	}

	err = docDir.Join("company.id").WriteAll(companyID.StringBytes())
	if err != nil {
		return nil, err
	}

	err = checkOutDir.MakeDir()
	if err != nil {
		return nil, err
	}

	err = c.makeCompanyDocumentDir(companyID, docID)
	if err != nil {
		return nil, err
	}

	status, err = c.writeDocumentCheckOutStatusFile(docID, docdb.VersionTime{}, userID, reason, checkOutDir)
	if err != nil {
		return nil, err
	}

	return status, nil
}

func (c *Conn) CheckedOutDocuments(ctx context.Context) (stati []*docdb.CheckOutStatus, err error) {
	defer errs.WrapWithFuncParams(&err)

	err = c.workspaceDir.ListDirInfoContext(ctx, func(dir fs.File, file fs.FileInfo) (err error) {
		docID, err := uu.IDFromString(dir.Name())
		if err != nil {
			return errs.Errorf("non UUID filename in workspace: %w", err)
		}
		if !file.Exists {
			log.Debug("CheckedOutDocuments: document is not checked out anymore, checkout dir gone").
				Ctx(ctx).
				UUID("docID", docID).
				Log()
			return nil
		}
		if !file.IsDir {
			return errs.Errorf("UUID named workspace %w", fs.NewErrIsNotDirectory(dir))
		}
		status, err := c.documentCheckOutStatus(docID)
		if err != nil {
			return err
		}
		if !status.Valid() {
			log.Debug("CheckedOutDocuments: document is not checked out anymore, missing checkout-status.json").
				Ctx(ctx).
				UUID("docID", docID).
				Log()
			return nil
		}

		stati = append(stati, status)
		return nil
	})
	if err != nil {
		return nil, err
	}

	return stati, nil
}

func (c *Conn) CheckOutDocument(ctx context.Context, docID, userID uu.ID, reason string) (checkOutStatus *docdb.CheckOutStatus, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, userID, reason)

	switch {
	case ctx.Err() != nil:
		return nil, ctx.Err()
	case !userID.Valid():
		return nil, errs.New("CheckOutDocument: invalid userID")
	case reason == "":
		return nil, errs.New("CheckOutDocument: reason must not be empty")
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	log, ctx = log.With().
		UUID("docID", docID).
		SubLoggerContext(ctx)

	log.Info("CheckOutDocument").
		UUID("userID", userID).
		Str("reason", reason).
		Log()

	checkOutStatus, err = c.documentCheckOutStatus(docID)
	if err != nil {
		return nil, err
	}
	if checkOutStatus != nil {
		return nil, docdb.NewErrDocumentCheckedOut(checkOutStatus)
	}

	versionInfo, versionDir, err := c.latestDocumentVersionInfo(docID)
	if err != nil {
		return nil, err
	}

	checkOutDir := c.CheckedOutDocumentDir(docID)
	if checkOutDir.Exists() {
		log.Debug("CheckOutDocument: workspace directory for document already exists, cleaning it up").Log()
		err = checkOutDir.RemoveRecursive()
		if err != nil {
			return nil, err
		}
	}

	err = fs.CopyRecursive(ctx, versionDir, checkOutDir)
	if err != nil {
		if e := checkOutDir.RemoveRecursive(); e != nil {
			err = errs.Errorf("error (%s) while cleaning up after error: %w", e, err)
		}
		return nil, errs.Errorf("CheckOutDocument: error while copying files to workspace directory: %w", err)
	}

	checkOutStatus, err = c.writeDocumentCheckOutStatusFile(docID, versionInfo.Version, userID, reason, checkOutDir)
	if err != nil {
		if e := checkOutDir.RemoveRecursive(); e != nil {
			err = errs.Errorf("error (%s) while cleaning up after error: %w", e, err)
		}
		return nil, errs.Errorf("CheckOutDocument: error while writing check out status file: %w", err)
	}

	return checkOutStatus, nil
}

func (c *Conn) removeCheckOutFiles(docID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, docID)

	if dir := c.CheckedOutDocumentDir(docID); dir.Exists() {
		err = dir.RemoveRecursive()
		if err != nil {
			return err
		}
	}
	return c.documentCheckOutStatusFile(docID).Remove()
}

func (c *Conn) CancelCheckOutDocument(ctx context.Context, docID uu.ID) (wasCheckedOut bool, lastVersion docdb.VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	if ctx.Err() != nil {
		return false, docdb.VersionTime{}, err
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	log, ctx = log.With().
		UUID("docID", docID).
		SubLoggerContext(ctx)

	log.Info("CancelCheckOutDocument").Log()

	status, err := c.documentCheckOutStatus(docID)
	wasCheckedOut = status.Valid()
	if err != nil {
		return false, docdb.VersionTime{}, err
	}
	if !wasCheckedOut {
		if checkOutDir := c.CheckedOutDocumentDir(docID); checkOutDir.Exists() {
			// Delete checked out workspace files if they exist even when
			// the checkout-status.json file does not exist anymore
			e := checkOutDir.RemoveRecursive()
			if e != nil {
				log.Error("Delete checked out workspace files that shouldn't be there").Err(e).Log()
			}
		}
		return false, docdb.VersionTime{}, nil
	}

	if status.Version.IsNull() {
		log.Debug("CancelCheckOutDocument ...removing new document").Log()
		err = c.removeCheckOutFiles(docID)
		if err != nil {
			return true, status.Version, err
		}

		docDir := c.documentDir(docID)
		return true, status.Version, uuiddir.RemoveDir(c.documentsDir, docDir)
	}

	return true, status.Version, c.removeCheckOutFiles(docID)
}

func (c *Conn) CheckInDocument(ctx context.Context, docID uu.ID) (versionInfo *docdb.VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	log, ctx = log.With().
		UUID("docID", docID).
		SubLoggerContext(ctx)

	var newVersionDir fs.File
	defer func() {
		if err != nil {
			if newVersionDir.IsDir() {
				e := newVersionDir.RemoveRecursive()
				if e != nil {
					err = errs.Errorf("error (%s) from cleaning up after CheckInDocument error: %w", e, err)
				}
			}

			log.Error("CheckInDocument error").Err(err).Log()
		}
	}()

	checkOutStatus, err := c.documentCheckOutStatus(docID)
	if err != nil {
		return nil, err
	}
	if !checkOutStatus.Valid() {
		return nil, docdb.NewErrDocumentNotCheckedOut(docID)
	}

	docDir := c.documentDir(docID)
	workDir := c.CheckedOutDocumentDir(docID)

	newVersion := docdb.NewVersionTime(ctx)
	newVersionDir = docDir.Join(newVersion.String())

	err = fs.CopyRecursive(ctx, workDir, newVersionDir)
	if err != nil {
		return nil, err
	}

	var prevVersionDir fs.File
	if checkOutStatus.Version.IsNotNull() {
		prevVersionDir = docDir.Join(checkOutStatus.Version.String())
	}

	versionInfo, err = docdb.NewVersionInfo(
		// checkOutStatus.CompanyID,
		docID,
		newVersion,
		checkOutStatus.Version,
		checkOutStatus.UserID,
		checkOutStatus.Reason,
		newVersionDir,
		prevVersionDir,
	)
	if err != nil {
		return nil, err
	}

	err = versionInfo.WriteJSON(docDir.Joinf("%s.json", newVersion))
	if err != nil {
		return nil, err
	}

	// Clean up after error checks if newVersionDir is set
	// to delete it after an error.
	// Disable the cleanup after all files have been copied
	// and before the checked out files get deleted,
	// so we don't loose files in case removing
	// the checked out files returns an error after
	// already deleting some files
	newVersionDir = ""

	err = c.removeCheckOutFiles(docID)
	if err != nil {
		err = errs.Errorf("CheckInDocument created new document version %s but can't remove check-out files: %w", newVersion, err)
	}

	log.Info("CheckInDocument").
		Stringer("version", newVersion).
		Log()

	return versionInfo, err
}

func (c *Conn) DeleteDocument(ctx context.Context, docID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	if ctx.Err() != nil {
		return ctx.Err()
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	log.Info("DeleteDocument").
		Ctx(ctx).
		UUID("docID", docID).
		Log()

	docDir := c.documentDir(docID)
	if docDir.Exists() {
		companyID, e := c.documentCompanyID(docID)
		if e == nil {
			e = uuiddir.Remove(c.companiesDir.Join(companyID.String()), docID)
		}
		err = errors.Join(err, e)

		e = uuiddir.RemoveDir(c.documentsDir, docDir)
		err = errors.Join(err, e)
	} else {
		err = docdb.NewErrDocumentNotFound(docID)
	}

	checkOutDir := c.CheckedOutDocumentDir(docID)
	if checkOutDir.Exists() {
		e := checkOutDir.RemoveRecursive()
		err = errors.Join(err, e)
	}

	return err
}

func (c *Conn) DeleteDocumentVersion(ctx context.Context, docID uu.ID, version docdb.VersionTime) (leftVersions []docdb.VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	log.Info("DeleteDocumentVersion").
		Ctx(ctx).
		UUID("docID", docID).
		Stringer("version", version).
		Log()

	docDir, versionDir, err := c.documentAndVersionDir(docID, version)
	if err != nil {
		return nil, err
	}

	err = versionDir.RemoveRecursive()
	if err != nil {
		return nil, err
	}

	versionInfoFile := docDir.Joinf("%s.json", version)
	if versionInfoFile.Exists() {
		err = versionInfoFile.Remove()
	}

	leftVersions, err = c.documentVersions(docID)
	if len(leftVersions) == 0 {
		// If no versions left, delete the company document entry
		// and the document directory
		companyID, e := c.documentCompanyID(docID)
		if e == nil {
			e = uuiddir.Remove(c.companiesDir.Join(companyID.String()), docID)
		}
		err = errors.Join(err, e)

		e = uuiddir.RemoveDir(c.documentsDir, docDir)
		err = errors.Join(err, e)
	}

	return leftVersions, err
}

// func (c *Conn) InsertDocumentVersion(ctx context.Context, docID uu.ID, version docdb.VersionTime, userID uu.ID, reason string, files []fs.FileReader) (info *docdb.VersionInfo, err error) {
// 	defer errs.WrapWithFuncParams(&err, ctx, docID, version, userID, reason, files)

// 	switch {
// 	case ctx.Err() != nil:
// 		return nil, ctx.Err()
// 	case !userID.Valid():
// 		return nil, errs.New("InsertDocumentVersion: invalid userID")
// 	case reason == "":
// 		return nil, errs.New("InsertDocumentVersion: reason must not be empty")
// 	}
// 	docMtx.Lock(docID)
// 	defer docMtx.Unlock(docID)

// 	docDir, versionDir, err := c.documentAndVersionDir(docID, version)
// 	switch {
// 	case err != nil:
// 		return nil, err
// 	case !docDir.Exists():
// 		return nil, docdb.NewErrDocumentNotFound(docID)
// 	case versionDir.Exists():
// 		return nil, docdb.NewErrDocumentVersionAlreadyExists(docID, version)
// 	}

// 	// TODO
// }

func (c *Conn) CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, files []fs.FileReader) (versionInfo *docdb.VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID, docID, userID, reason, files)

	if err = ctx.Err(); err != nil {
		return nil, err
	}
	if err = companyID.Validate(); err != nil {
		return nil, err
	}
	if err = docID.Validate(); err != nil {
		return nil, err
	}
	if err = userID.Validate(); err != nil {
		return nil, err
	}

	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	docDir := c.documentDir(docID)
	if docDir.IsDir() {
		return nil, docdb.NewErrDocumentAlreadyExists(docID)
	}

	newVersion := docdb.NewVersionTime(ctx)
	newVersionDir := docDir.Join(newVersion.String())

	defer func() {
		if err != nil {
			if docDir.Exists() {
				e := uuiddir.RemoveDir(c.documentsDir, docDir)
				err = errors.Join(err, e)
			}
			e := c.removeCompanyDocumentDirIfExists(companyID, docID)
			err = errors.Join(err, e)
		}
	}()

	err = newVersionDir.MakeAllDirs()
	if err != nil {
		return nil, err
	}

	err = docDir.Join("company.id").WriteAll(companyID.StringBytes())
	if err != nil {
		return nil, err
	}

	err = c.makeCompanyDocumentDir(companyID, docID)
	if err != nil {
		return nil, err
	}

	for _, file := range files {
		err = fs.CopyFile(ctx, file, newVersionDir)
		if err != nil {
			return nil, err
		}
	}

	// NewVersionInfo reads newVersionDir, this could be optimized
	// by copying and content hashing the files in one loop
	versionInfo, err = docdb.NewVersionInfo(
		docID,
		newVersion,
		docdb.VersionTime{},
		userID,
		reason,
		newVersionDir,
		"",
	)
	if err != nil {
		return nil, err
	}
	err = versionInfo.WriteJSON(docDir.Joinf("%s.json", newVersion))
	if err != nil {
		return nil, err
	}

	return versionInfo, nil
}

func (c *Conn) AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, tx docdb.AddVersionTx) (versionInfo *docdb.VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, userID, reason, tx)

	if err = ctx.Err(); err != nil {
		return nil, err
	}
	if err = docID.Validate(); err != nil {
		return nil, err
	}
	if err = userID.Validate(); err != nil {
		return nil, err
	}
	if tx == nil {
		return nil, errs.New("nil tx passed to AddDocumentVersion")
	}

	docDir := c.documentDir(docID)
	newVersion := docdb.NewVersionTime(ctx)
	newVersionDir := docDir.Join(newVersion.String())
	versionInfoFile := docDir.Joinf("%s.json", newVersion)

	docMtx.Lock(docID)
	defer docMtx.Unlock(docID)

	defer func() {
		if err != nil {
			if docDir.Exists() {
				err = errors.Join(err, newVersionDir.RemoveRecursive())
			}
			if versionInfoFile.Exists() {
				err = errors.Join(err, versionInfoFile.Remove())
			}
		}
	}()

	prevVersionInfo, prevVersionDir, err := c.latestDocumentVersionInfo(docID)
	if err != nil {
		return nil, err
	}

	writeFiles, deleteFiles, newCompanyID, err := safelyCallAddVersionTx(ctx, prevVersionInfo.Version, docdb.DirFileProvider(prevVersionDir), tx)
	if err != nil {
		return nil, err
	}
	for _, f := range writeFiles {
		if !f.Exists() {
			return nil, errs.Errorf("file returned for new document version does not exist: %#v", f)
		}
	}

	err = newVersionDir.MakeDir()
	if err != nil {
		return nil, err
	}

	// Copy previous version files that are not in writeFiles or deleteFiles
	for filename := range prevVersionInfo.Files {
		if fs.FileReaderNameIndex(writeFiles, filename) >= 0 || slices.Contains(deleteFiles, filename) {
			continue
		}
		err = fs.CopyFile(ctx, prevVersionDir.Join(filename), newVersionDir)
		if err != nil {
			return nil, err
		}
	}

	// Write new files of version
	for _, writeFile := range writeFiles {
		err = fs.CopyFile(ctx, writeFile, newVersionDir)
		if err != nil {
			return nil, err
		}
	}

	// NewVersionInfo reads newVersionDir and prevVersionDir, this could be optimized
	// by copying and content hashing the files in one loop
	versionInfo, err = docdb.NewVersionInfo(
		docID,
		newVersion,
		prevVersionInfo.Version,
		userID,
		reason,
		newVersionDir,
		prevVersionDir,
	)
	if err != nil {
		return nil, err
	}

	if versionInfo.EqualFiles(prevVersionInfo) {
		return nil, docdb.ErrNoChanges
	}

	err = versionInfo.WriteJSON(versionInfoFile)
	if err != nil {
		return nil, err
	}

	// Change company ID as last step after everything else succeeded
	if newCompanyID != nil {
		err = c.setDocumentCompanyID(docID, *newCompanyID)
		if err != nil {
			return nil, err
		}
	}

	return versionInfo, nil
}

func safelyCallAddVersionTx(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider, tx docdb.AddVersionTx) (writeFiles []fs.FileReader, deleteFiles []string, newCompanyID *uu.ID, err error) {
	defer errs.RecoverPanicAsError(&err)

	return tx(ctx, prevVersion, prevFiles)
}
