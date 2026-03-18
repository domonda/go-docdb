package localfsdb

import (
	"context"
	"errors"
	"fmt"
	"os"
	"slices"
	"testing"

	"github.com/ungerik/go-fs"
	"github.com/ungerik/go-fs/uuiddir"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

// Compiler check if *Conn implements docdb.Conn
var _ docdb.Conn = new(Conn)

type Conn struct {
	documentsDir fs.File

	// companiesDir contains directories named by the UUID of a company.
	// Within each company directory, every document of that company will be
	// represented by a directory named by the UUID of the document.
	// Directories are used as atomic, threadsafe filesystem level
	// mapping mechanism between companyID and docID.
	companiesDir fs.File
}

func NewConn(documentsDir, companiesDir fs.File) *Conn {
	if !documentsDir.IsDir() {
		panic("documentsDir does not exist: '" + string(documentsDir) + "'")
	}
	if documentsDir.FileSystem() != fs.Local {
		panic("documentsDir is not on local file-system: '" + string(documentsDir) + "'")
	}
	if !companiesDir.IsDir() {
		panic("companiesDir does not exist: '" + string(companiesDir) + "'")
	}
	if companiesDir.FileSystem() != fs.Local {
		panic("companiesDir is not on local file-system: '" + string(companiesDir) + "'")
	}
	return &Conn{
		documentsDir: documentsDir,
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
	companiesDir := dir.Join("companies")

	err = documentsDir.MakeDir()
	if err != nil {
		t.Fatal(err)
	}
	err = companiesDir.MakeDir()
	if err != nil {
		t.Fatal(err)
	}

	return NewConn(
		documentsDir,
		companiesDir,
	)
}

func (c *Conn) String() string {
	return fmt.Sprintf(
		"localfsdb.Conn{Documents: %q}",
		c.documentsDir.LocalPath(),
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

// companyDocumentDir returns the marker directory for a document of a company
// the existence of this directory acts as a threadsafe marker that a docID belongs to a companyID.
func (c *Conn) companyDocumentDir(companyID, docID uu.ID) fs.File {
	companyDir := c.companiesDir.Join(companyID.String())
	return uuiddir.Join(companyDir, docID)
}

func (c *Conn) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	if err = ctx.Err(); err != nil {
		return false, err
	}

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
	return c.companyDocumentDir(companyID, docID).MakeAllDirs()
}

func (c *Conn) removeCompanyDocumentDirIfExists(companyID, docID uu.ID) error {
	docDir := c.companyDocumentDir(companyID, docID)
	if !docDir.Exists() {
		return nil
	}
	companyDir := c.companiesDir.Join(companyID.String())
	return uuiddir.RemoveDir(companyDir, docDir)
}

func (c *Conn) latestDocumentVersionInfo(ctx context.Context, docID uu.ID) (versionInfo *docdb.VersionInfo, versionDir fs.File, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	docDir := c.documentDir(docID)
	if !docDir.IsDir() {
		return nil, "", docdb.NewErrDocumentNotFound(docID)
	}

	var latestVersion docdb.VersionTime
	err = enumVersionDirs(ctx, docDir, docID, func(version docdb.VersionTime, dir fs.File) {
		if version.Time.After(latestVersion.Time) {
			latestVersion = version
			versionDir = dir
		}
	})
	if err != nil {
		return nil, "", err
	}

	if latestVersion.Time.IsZero() {
		return nil, "", errs.Errorf("document %s directory exists but has no version subdirectories: %w", docID, docdb.NewErrDocumentNotFound(docID))
	}

	versionInfo, _, err = c.documentVersionInfo(docID, latestVersion)
	if err != nil {
		return nil, "", err
	}

	return versionInfo, versionDir, nil
}

func (c *Conn) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	if err = ctx.Err(); err != nil {
		return uu.IDNil, err
	}

	return c.documentCompanyID(ctx, docID)
}

func (c *Conn) documentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	file := c.documentDir(docID).Join("company.id")
	if file.Exists() {
		uuidStr, err := file.ReadAllString()
		if err != nil {
			return uu.IDNil, err
		}
		return uu.IDFromString(uuidStr)
	}

	// Backward compatible way, when no company.id file exists:
	version, versionDir, err := c.latestDocumentVersionInfo(ctx, docID)
	if err != nil {
		return uu.IDNil, err
	}
	var doc struct {
		CompanyID uu.ID `json:"companyId"`
	}
	err = versionDir.Join("doc.json").ReadJSON(ctx, &doc)
	if err != nil {
		return uu.IDNil, err
	}
	if doc.CompanyID.IsNil() {
		return uu.IDNil, errs.Errorf("document %s version %s/doc.json has no companyId", docID, version.Version)
	}

	return doc.CompanyID, nil
}

func (c *Conn) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, companyID)

	if err = ctx.Err(); err != nil {
		return err
	}

	docWriteMtx.Lock(docID)
	defer docWriteMtx.Unlock(docID)

	return c.setDocumentCompanyID(ctx, docID, companyID)
}

func (c *Conn) setDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, companyID)

	if err = companyID.Validate(); err != nil {
		return err
	}

	docDir := c.documentDir(docID)
	if !docDir.Exists() {
		return docdb.NewErrDocumentNotFound(docID)
	}

	currCompanyID, err := c.documentCompanyID(ctx, docID)
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

	if err = ctx.Err(); err != nil {
		return nil, err
	}

	return c.documentVersions(ctx, docID)
}

func (c *Conn) documentVersions(ctx context.Context, docID uu.ID) (versions []docdb.VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	docDir := c.documentDir(docID)
	if !docDir.IsDir() {
		return nil, nil
	}
	err = enumVersionDirs(ctx, docDir, docID, func(version docdb.VersionTime, dir fs.File) {
		versions = append(versions, version)
	})
	if err != nil {
		return nil, err
	}
	slices.SortFunc(versions, func(a, b docdb.VersionTime) int { return a.Compare(b) })
	return versions, nil
}

// enumVersionDirs lists version subdirectories of docDir that have
// a corresponding .json info file. It skips directories that can't be
// parsed as a VersionTime or are missing the info JSON file.
func enumVersionDirs(ctx context.Context, docDir fs.File, docID uu.ID, callback func(version docdb.VersionTime, dir fs.File)) error {
	return docDir.ListDirInfo(func(dirInfo *fs.FileInfo) error {
		if !dirInfo.IsDir || dirInfo.IsHidden {
			return nil
		}
		version, err := docdb.VersionTimeFromString(dirInfo.Name)
		if err != nil {
			log.ErrorCtx(ctx, "Can't parse document sub-directory name as version, skipping version and continuing...").
				UUID("docID", docID).
				Str("dirName", dirInfo.Name).
				Str("dirPath", dirInfo.File.Path()).
				Err(err).
				Log()
			return nil
		}
		infoFile := docDir.Join(version.String() + ".json")
		if !infoFile.Exists() {
			versionFiles, err := dirInfo.File.ListDirMax(20)
			if err != nil {
				log.ErrorCtx(ctx, "Error listing document version directory").Err(err).Log()
			}
			log.ErrorCtx(ctx, "Document version directory has no corresponding version info JSON file, skipping version and continuing...").
				UUID("docID", docID).
				Str("jsonFile", infoFile.Name()).
				Str("versionDir", dirInfo.Name).
				Strs("versionFiles", fs.FileNames(versionFiles)).
				Str("docDir", docDir.Path()).
				Log()
			return nil
		}
		callback(version, dirInfo.File)
		return nil
	})
}

func (c *Conn) documentVersionInfo(docID uu.ID, version docdb.VersionTime) (versionInfo *docdb.VersionInfo, docDir fs.File, err error) {
	defer errs.WrapWithFuncParams(&err, docID, version)

	if err := version.Validate(); err != nil {
		return nil, "", err
	}

	docDir = c.documentDir(docID)
	if !docDir.IsDir() {
		return nil, docDir, docdb.NewErrDocumentNotFound(docID)
	}

	infoFile := docDir.Join(version.String() + ".json")
	versionInfo, err = readAndFixVersionInfoJSON(infoFile, true)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			log.Warn("Document version JSON file not found").
				Err(err).
				UUID("docID", docID).
				Stringer("version", version).
				Str("filename", infoFile.Name()).
				Log()
			err = errs.Errorf("document %s version %s directory exists but version info JSON file is missing: %w", docID, version, docdb.NewErrDocumentVersionNotFound(docID, version))
		}
		return nil, docDir, err
	}

	// Older implementations did not include VersionInfo.CompanyID
	// so read latest state from "company.id"
	if versionInfo.CompanyID.IsNil() {
		file := docDir.Join("company.id")
		uuidStr, err := file.ReadAllString()
		if err != nil {
			return nil, "", errs.Errorf("document %s can't read company ID because %w", docID, err)
		}
		versionInfo.CompanyID, err = uu.IDFromString(uuidStr)
		if err != nil {
			return nil, "", errs.Errorf("document %s can't read company ID because %w", docID, err)
		}
	}

	return versionInfo, docDir, nil
}

func (c *Conn) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (versionInfo *docdb.VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	if err = ctx.Err(); err != nil {
		return nil, err
	}

	versionInfo, _, err = c.documentVersionInfo(docID, version)
	if err != nil {
		return nil, err
	}

	return versionInfo, nil
}

func (c *Conn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (versionInfo *docdb.VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	if err = ctx.Err(); err != nil {
		return nil, err
	}

	versionInfo, _, err = c.latestDocumentVersionInfo(ctx, docID)
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

	if err = ctx.Err(); err != nil {
		return nil, err
	}

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

	if err = ctx.Err(); err != nil {
		return nil, err
	}

	_, versionDir, err := c.documentAndVersionDir(docID, version)
	if err != nil {
		return nil, err
	}
	return docdb.DirFileProvider(versionDir), nil
}

func (c *Conn) DeleteDocument(ctx context.Context, docID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID)

	if ctx.Err() != nil {
		return ctx.Err()
	}
	docWriteMtx.Lock(docID)
	defer docWriteMtx.Unlock(docID)

	log.InfoCtx(ctx, "DeleteDocument").
		UUID("docID", docID).
		Log()

	docDir := c.documentDir(docID)
	if !docDir.Exists() {
		return docdb.NewErrDocumentNotFound(docID)
	}

	companyID, err := c.documentCompanyID(ctx, docID)
	if err == nil {
		err = uuiddir.Remove(c.companiesDir.Join(companyID.String()), docID)
	}

	return errors.Join(err, uuiddir.RemoveDir(c.documentsDir, docDir))
}

func (c *Conn) DeleteDocumentVersion(ctx context.Context, docID uu.ID, version docdb.VersionTime) (leftVersions []docdb.VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	docWriteMtx.Lock(docID)
	defer docWriteMtx.Unlock(docID)

	log.InfoCtx(ctx, "DeleteDocumentVersion").
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
		if removeErr := versionInfoFile.Remove(); removeErr != nil {
			err = errors.Join(err, removeErr)
		}
	}

	leftVersions, lErr := c.documentVersions(ctx, docID)
	err = errors.Join(err, lErr)
	if len(leftVersions) == 0 {
		// If no versions left, delete the company document entry
		// and the document directory
		companyID, e := c.documentCompanyID(ctx, docID)
		if e == nil {
			e = uuiddir.Remove(c.companiesDir.Join(companyID.String()), docID)
		}
		err = errors.Join(err, e)

		e = uuiddir.RemoveDir(c.documentsDir, docDir)
		err = errors.Join(err, e)
	}

	return leftVersions, err
}

func (c *Conn) CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, newVersion docdb.VersionTime, files []fs.FileReader, onNewVersion docdb.OnNewVersionFunc) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID, docID, userID, reason, newVersion, files, onNewVersion)

	if err = ctx.Err(); err != nil {
		return err
	}
	if err = companyID.Validate(); err != nil {
		return err
	}
	if err = docID.Validate(); err != nil {
		return err
	}
	if err = userID.Validate(); err != nil {
		return err
	}
	if err := newVersion.Validate(); err != nil {
		return err
	}
	if onNewVersion == nil {
		return errs.New("nil onNewVersion func passed to CreateDocument")
	}

	docWriteMtx.Lock(docID)
	defer docWriteMtx.Unlock(docID)

	docDir := c.documentDir(docID)
	if docDir.IsDir() {
		return docdb.NewErrDocumentAlreadyExists(docID)
	}

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
		return err
	}

	err = docDir.Join("company.id").WriteAll(companyID.StringBytes())
	if err != nil {
		return err
	}

	err = c.makeCompanyDocumentDir(companyID, docID)
	if err != nil {
		return err
	}

	for _, file := range files {
		err = fs.CopyFile(ctx, file, newVersionDir)
		if err != nil {
			return err
		}
	}

	// NewVersionInfo reads newVersionDir, this could be optimized
	// by copying and content hashing the files in one loop
	versionInfo, err := newVersionInfo(
		companyID,
		docID,
		newVersion,
		nil, // prevVersion
		userID,
		reason,
		newVersionDir,
		fs.InvalidFile, // prevVersionDir
	)
	if err != nil {
		return err
	}
	err = versionInfo.WriteJSON(docDir.Joinf("%s.json", newVersion))
	if err != nil {
		return err
	}

	return safelyCallOnNewVersionFunc(ctx, versionInfo, onNewVersion)
}

func (c *Conn) AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, createVersion docdb.CreateVersionFunc, onNewVersion docdb.OnNewVersionFunc) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, userID, reason, createVersion, onNewVersion)

	if err = ctx.Err(); err != nil {
		return err
	}
	if err = docID.Validate(); err != nil {
		return err
	}
	if err = userID.Validate(); err != nil {
		return err
	}
	if createVersion == nil {
		return errs.New("nil createVersion func passed to AddDocumentVersion")
	}
	if onNewVersion == nil {
		return errs.New("nil onNewVersion func passed to AddDocumentVersion")
	}

	var (
		newVersionDir      fs.File
		newVersionInfoFile fs.File
	)
	defer func() {
		if err != nil {
			if newVersionDir.Exists() {
				err = errors.Join(err, newVersionDir.RemoveRecursive())
			}
			if newVersionInfoFile.Exists() {
				err = errors.Join(err, newVersionInfoFile.Remove())
			}
		}
	}()

	docWriteMtx.Lock(docID)
	defer docWriteMtx.Unlock(docID)

	prevVersionInfo, prevVersionDir, err := c.latestDocumentVersionInfo(ctx, docID)
	if err != nil {
		return err
	}

	result, err := safelyCallCreateVersionFunc(
		ctx,
		docID,
		prevVersionInfo.Version,
		docdb.DirFileProvider(prevVersionDir),
		createVersion,
	)
	if err != nil {
		return err
	}
	if err := result.Validate(); err != nil {
		return err
	}
	if !result.Version.After(prevVersionInfo.Version) {
		return errs.Errorf("version %s returned from CreateVersionFunc is not after previous version %s", result.Version, prevVersionInfo.Version)
	}

	docDir := c.documentDir(docID)
	newVersionDir = docDir.Join(result.Version.String())
	newVersionInfoFile = docDir.Joinf("%s.json", result.Version)

	if newVersionDir.Exists() {
		return errs.Errorf("new version %s directory already exists", result.Version)
	}
	err = newVersionDir.MakeDir()
	if err != nil {
		return err
	}

	// Copy previous version files that are not in writeFiles or deleteFiles
	for filename := range prevVersionInfo.Files {
		if fs.NameIndex(result.WriteFiles, filename) >= 0 || slices.Contains(result.RemoveFiles, filename) {
			continue // Don't copy writeFiles or deleteFiles
		}
		err = fs.CopyFile(ctx, prevVersionDir.Join(filename), newVersionDir)
		if err != nil {
			return err
		}
	}

	// Write new files of version
	for _, writeFile := range result.WriteFiles {
		err = fs.CopyFile(ctx, writeFile, newVersionDir)
		if err != nil {
			return err
		}
	}

	companyID := result.NewCompanyID.GetOr(prevVersionInfo.CompanyID)

	// NewVersionInfo reads newVersionDir and prevVersionDir, this could be optimized
	// by copying and content hashing the files in one loop
	versionInfo, err := newVersionInfo(
		companyID,
		docID,
		result.Version,
		&prevVersionInfo.Version,
		userID,
		reason,
		newVersionDir,
		prevVersionDir,
	)
	if err != nil {
		return err
	}

	if versionInfo.EqualFiles(prevVersionInfo) {
		return docdb.ErrNoChanges
	}

	err = versionInfo.WriteJSON(newVersionInfoFile)
	if err != nil {
		return err
	}

	// Change company as last step after everything else succeeded
	if companyID != prevVersionInfo.CompanyID {
		err = c.setDocumentCompanyID(ctx, docID, companyID)
		if err != nil {
			return err
		}
	}

	err = safelyCallOnNewVersionFunc(ctx, versionInfo, onNewVersion)
	if err != nil {
		// Undo company change
		if companyID != prevVersionInfo.CompanyID {
			err = errors.Join(err, c.setDocumentCompanyID(ctx, docID, prevVersionInfo.CompanyID))
		}
		return err
	}

	return nil
}

func (c *Conn) AddMultiDocumentVersion(ctx context.Context, docIDs uu.IDSlice, userID uu.ID, reason string, createVersion docdb.CreateVersionFunc, onNewVersion docdb.OnNewVersionFunc) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docIDs, userID, reason, createVersion, onNewVersion)

	return docdb.AddMultiDocumentVersionImpl(ctx, c, docIDs, userID, reason, createVersion, onNewVersion)
}

func safelyCallCreateVersionFunc(ctx context.Context, docID uu.ID, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider, createVersion docdb.CreateVersionFunc) (result *docdb.CreateVersionResult, err error) {
	defer errs.RecoverPanicAsError(&err)

	return createVersion(ctx, docID, prevVersion, prevFiles)
}

func safelyCallOnNewVersionFunc(ctx context.Context, versionInfo *docdb.VersionInfo, onNewVersion docdb.OnNewVersionFunc) (err error) {
	defer errs.RecoverPanicAsError(&err)

	return onNewVersion(ctx, versionInfo)
}

// newVersionInfo builds a VersionInfo by reading file hashes from versionDir
// and diffing against prevVersionDir (if not "").
func newVersionInfo(ctx context.Context, companyID, docID uu.ID, version docdb.VersionTime, prevVersion *docdb.VersionTime, commitUserID uu.ID, commitReason string, versionDir, prevVersionDir fs.File) (versionInfo *docdb.VersionInfo, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID, docID, version, prevVersion, commitUserID, commitReason, versionDir, prevVersionDir)

	if (prevVersion == nil) != (prevVersionDir == "") {
		return nil, errs.New("prevVersion and prevVersionDir must either both be set or both be empty")
	}

	versionInfo = &docdb.VersionInfo{
		CompanyID:    companyID,
		DocID:        docID,
		Version:      version,
		PrevVersion:  prevVersion,
		CommitUserID: commitUserID,
		CommitReason: commitReason,
		Files:        make(map[string]docdb.FileInfo),
	}

	err = versionDir.ListDir(func(file fs.File) error {
		filename := file.Name()
		versionInfo.Files[filename], err = docdb.ReadFileInfo(ctx, file)
		return err
	})
	if err != nil {
		return nil, err
	}

	if prevVersionDir == "" {
		for filename := range versionInfo.Files {
			versionInfo.AddedFiles = append(versionInfo.AddedFiles, filename)
		}
	} else {
		prevVersionFiles := make(map[string]docdb.FileInfo)
		err = prevVersionDir.ListDir(func(file fs.File) error {
			filename := file.Name()
			prevVersionFiles[filename], err = docdb.ReadFileInfo(ctx, file)
			return err
		})
		if err != nil {
			return nil, err
		}

		for filename, versionFileInfo := range versionInfo.Files {
			prevVersionFile, prevVersionHasFile := prevVersionFiles[filename]
			if prevVersionHasFile {
				if versionFileInfo.Hash != prevVersionFile.Hash {
					versionInfo.ModifiedFiles = append(versionInfo.ModifiedFiles, filename)
				}
			} else {
				versionInfo.AddedFiles = append(versionInfo.AddedFiles, filename)
			}
		}
		for filename := range prevVersionFiles {
			if _, versionHasFile := versionInfo.Files[filename]; !versionHasFile {
				versionInfo.RemovedFiles = append(versionInfo.RemovedFiles, filename)
			}
		}
	}

	slices.Sort(versionInfo.AddedFiles)
	slices.Sort(versionInfo.RemovedFiles)
	slices.Sort(versionInfo.ModifiedFiles)

	return versionInfo, nil
}

func (c *Conn) RestoreDocument(ctx context.Context, doc *docdb.HashedDocument, merge bool) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, doc, merge)

	return errs.Errorf("RestoreDocument is %w for localfsdb.Conn", docdb.ErrNotImplemented)
}

// readAndFixVersionInfoJSON reads a VersionInfo from a JSON file.
// It handles a legacy format where ModifiedFiles was misspelled as "ModidfiedFiles".
// If writeFixedVersion is true and the legacy field is found, the file is rewritten
// with the corrected field name.
func readAndFixVersionInfoJSON(file fs.File, writeFixedVersion bool) (versionInfo *docdb.VersionInfo, err error) {
	var i struct {
		docdb.VersionInfo
		ModidfiedFiles []string // with typo
	}
	err = file.ReadJSON(context.Background(), &i)
	if err != nil {
		return nil, err
	}
	if len(i.ModidfiedFiles) > 0 && len(i.ModifiedFiles) == 0 {
		i.ModifiedFiles = i.ModidfiedFiles
		if writeFixedVersion {
			log.Info("Fixing old VersionInfo format").Str("file", string(file)).Log()
			err = i.VersionInfo.WriteJSON(file)
			if err != nil {
				return nil, err
			}
		} else {
			log.Info("Loading old VersionInfo format").Str("file", string(file)).Log()
		}
	}
	return &i.VersionInfo, nil
}
