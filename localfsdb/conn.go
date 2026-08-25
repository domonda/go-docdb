package localfsdb

import (
	"context"
	"encoding/json"
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
		cleanupErr := dir.RemoveDirContentsRecursive()
		if cleanupErr != nil {
			t.Errorf("can't clean up docdb test-dir %s because of: %s", dir.Path(), cleanupErr)
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

func (c *Conn) CompanyIDs(ctx context.Context) (companyIDs uu.IDSlice, err error) {
	defer errs.WrapWithFuncParams(&err, ctx)

	// companiesDir holds one sub-directory per company, named by the company's
	// UUID. List those directory names and parse each back into a company ID.
	err = c.companiesDir.ListDirInfoContext(ctx, func(info *fs.FileInfo) error {
		if !info.IsDir || info.IsHidden {
			return nil
		}
		companyID, e := uu.IDFromString(info.Name)
		if e != nil {
			log.ErrorCtx(ctx, "companies directory contains a sub-directory that is not a company UUID, skipping and continuing...").
				Str("dirName", info.Name).
				Str("dirPath", info.File.Path()).
				Err(e).
				Log()
			return nil
		}
		companyIDs = append(companyIDs, companyID)
		return nil
	})
	if err != nil {
		return nil, err
	}
	companyIDs.Sort() // Sort by ID for a consistent order
	return companyIDs, nil
}

func (c *Conn) CompanyDocumentIDs(ctx context.Context, companyID uu.ID) (docIDs uu.IDSlice, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, companyID)

	companyDir := c.companiesDir.Join(companyID.String())
	info := companyDir.Info()
	switch {
	case !info.Exists:
		// No documents have ever been stored for this company, so the company
		// directory does not exist. Return nil instead of enumerating a missing
		// directory (which would error), matching the empty-result behavior of
		// other backends.
		return nil, nil
	case !info.IsDir:
		// The path exists but is not a directory: surface this on-disk
		// inconsistency instead of silently reporting the company as empty.
		return nil, errs.Errorf("company path %s exists but is not a directory", companyDir.Path())
	}

	err = uuiddir.Enum(
		ctx,
		companyDir,
		func(docDir fs.File, id [16]byte) error {
			docIDs = append(docIDs, id)
			return nil
		},
	)
	if err != nil {
		return nil, err
	}
	docIDs.Sort() // Sort by ID for a consistent order
	return docIDs, nil
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

	versionInfo, _, err = c.documentVersionInfo(ctx, docID, latestVersion)
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
		return nil, docdb.NewErrDocumentNotFound(docID)
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

func (c *Conn) documentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (versionInfo *docdb.VersionInfo, docDir fs.File, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, version)

	if err = version.Validate(); err != nil {
		return nil, "", err
	}

	docDir = c.documentDir(docID)
	if !docDir.IsDir() {
		return nil, docDir, docdb.NewErrDocumentNotFound(docID)
	}

	infoFile := docDir.Join(version.String() + ".json")
	versionInfo, err = readAndFixVersionInfoJSON(ctx, infoFile, true)
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

	versionInfo, _, err = c.documentVersionInfo(ctx, docID, version)
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

	// The predecessor this version's successor has to take over, read before
	// the version is removed. A version whose info file is missing or unreadable
	// — a half-written version, which this method exists to clean up after —
	// names no predecessor that can be recovered, and its successor is left
	// alone like a genesis delete leaves it below.
	versionInfoFile := docDir.Joinf("%s.json", version)
	var deletedPrevVersion *docdb.VersionTime
	if versionInfoFile.Exists() {
		deletedInfo, infoErr := readAndFixVersionInfoJSON(ctx, versionInfoFile, false)
		if infoErr != nil {
			// Deleted anyway, with the relink skipped, rather than refused. An
			// unreadable info file is one of the states a crash mid-write
			// leaves behind, so refusing here made the versions this method
			// exists to remove the ones it could not remove: the only way out
			// was deleting the file by hand, and until someone did,
			// enumVersionDirs reported the version on every read of the
			// document.
			//
			// The predecessor to hand the successor to is recorded in this file
			// alone, so it is lost with it and the successor keeps naming a
			// version that is gone. That is the same state a genesis delete
			// leaves behind, it is visible rather than silent, and a
			// merge-restore of the deleted version undoes it by taking the
			// version back.
			log.ErrorCtx(ctx, "Can't read version info JSON file of the version being deleted, deleting it without relinking its successor...").
				Err(infoErr).
				UUID("docID", docID).
				Stringer("version", version).
				Str("jsonFile", versionInfoFile.Path()).
				Log()
		} else {
			deletedPrevVersion = deletedInfo.PrevVersion
		}
	}

	err = versionDir.RemoveRecursive()
	if err != nil {
		return nil, err
	}

	if versionInfoFile.Exists() {
		err = errors.Join(err, versionInfoFile.Remove())
	}

	// The deleted version's successor is chained onto the deleted version's own
	// predecessor, so no version is left naming one the document no longer has.
	// This is what pgstore does in the same call, and RestoreDocument on both
	// implementations undoes exactly this relink when the version is restored
	// (see CreateDocumentVersionInput.RelinkSuccessor); leaving the successor on
	// the removed version instead made the two answer differently for the same
	// delete, and a caller walking the chain backwards ran into a predecessor
	// that DocumentVersions does not list.
	//
	// Nothing is relinked when the deleted version had no predecessor of its
	// own, which is the rule pgstore deletes by as well: the successor of a
	// deleted genesis version keeps naming it, so a merge-restore of the
	// earliest version takes it back rather than filling a second version in
	// front of a successor that has already become a genesis itself.
	if deletedPrevVersion != nil {
		err = errors.Join(err, relinkSuccessorsOfDeletedVersion(ctx, docDir, docID, version, *deletedPrevVersion))
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
	} else if version.After(leftVersions[len(leftVersions)-1]) {
		// A document belongs to the company of its latest version, so deleting
		// the latest version of a document that was moved between companies
		// re-assigns it to the company of the version that becomes the latest
		// one — otherwise the document would stay listed under a company that
		// none of its remaining versions names.
		//
		// Only for a delete that actually removed the latest version, which is
		// what documentVersions returning nothing after it proves: leftVersions
		// is ascending, so version being after the last of them is what makes
		// it the one that was on top. Re-deriving the company after deleting an
		// older version instead would overwrite a company marker that
		// SetDocumentCompanyID moved without committing a version — that marker
		// names a company no version of the document names, on purpose, and
		// deleting a version that cannot affect ownership must leave it alone.
		// leftVersions is ascending and its last entry is the version that
		// becomes the latest, so its info file is read directly instead of
		// re-enumerating the document directory to rediscover it.
		latestVersionInfo, _, e := c.documentVersionInfo(ctx, docID, leftVersions[len(leftVersions)-1])
		if e == nil {
			e = c.setDocumentCompanyID(ctx, docID, latestVersionInfo.CompanyID)
		}
		err = errors.Join(err, e)
	}

	return leftVersions, err
}

// diagnosePathConflict walks targetPath from the leaf toward basePath looking
// for the first non-directory entry. If found, returns an [docdb.ErrPathConflict]
// describing the offending on-disk entry; otherwise returns nil. basePath is
// the inclusive lower bound of the walk and is never inspected itself.
//
// Used to enrich [os.ErrExist] errors from MakeAllDirs so operators can see
// which exact path component is occupied by a regular file, symlink, or other
// non-directory entry.
func diagnosePathConflict(companyID, docID uu.ID, basePath, targetPath fs.File) error {
	cur := targetPath
	for cur.Path() != basePath.Path() {
		info := cur.Info()
		if info.Exists {
			if info.IsDir {
				return nil
			}
			entryType := "irregular entry"
			switch {
			case info.IsRegular:
				entryType = "regular file"
			case fs.Local.IsSymbolicLink(cur.LocalPath()):
				entryType = "symbolic link"
			}
			return docdb.NewErrPathConflict(
				docID, companyID,
				string(targetPath),
				string(cur),
				entryType,
				info.Size,
				info.Modified,
			)
		}
		parent := cur.Dir()
		if parent.Path() == cur.Path() {
			return nil
		}
		cur = parent
	}
	return nil
}

// wrapMakeAllDirsErr returns origErr enriched with a [docdb.ErrPathConflict]
// when a non-directory entry can be located along targetPath. The original
// error is preserved via [errors.Join] so log searches for the underlying
// "file already exists" / "file is not a directory" / "not a directory"
// messages still match.
//
// Runs unconditionally on any non-nil origErr because the underlying failure
// can surface as [os.ErrExist] (ErrAlreadyExists wrap), [syscall.ENOTDIR]
// (raw os.MkdirAll), or [fs.ErrIsNotDirectory] (go-fs Stat path) depending
// on which code path triggered it. The diagnose walk does its own Stat per
// component, so a no-op (no non-dir found) leaves origErr untouched.
func wrapMakeAllDirsErr(companyID, docID uu.ID, basePath, targetPath fs.File, origErr error) error {
	if origErr == nil {
		return nil
	}
	if conflict := diagnosePathConflict(companyID, docID, basePath, targetPath); conflict != nil {
		return errors.Join(origErr, conflict)
	}
	return origErr
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
	if err = newVersion.Validate(); err != nil {
		return err
	}
	if onNewVersion == nil {
		return errs.New("nil onNewVersion func passed to CreateDocument")
	}
	if len(files) == 0 {
		// The first version of a document must contain at least one file:
		// a document cannot start with an empty, change-less version.
		return errs.Errorf("cannot create document %s without files", docID)
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
	// Turn a panic into the error the rollback above keys on: registered after
	// it so it runs first, and deferred directly because recover only recovers
	// when the deferred function calls it itself — from inside the rollback
	// closure it would return nil and the panic would escape with the
	// half-created document left on disk.
	defer errs.RecoverPanicAsError(&err)

	err = newVersionDir.MakeAllDirs()
	if err != nil {
		return wrapMakeAllDirsErr(companyID, docID, c.documentsDir, newVersionDir, err)
	}

	err = docDir.Join("company.id").WriteAll(companyID.StringBytes())
	if err != nil {
		return err
	}

	err = c.makeCompanyDocumentDir(companyID, docID)
	if err != nil {
		return wrapMakeAllDirsErr(companyID, docID, c.companiesDir.Join(companyID.String()), c.companyDocumentDir(companyID, docID), err)
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
		ctx,
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

	docWriteMtx.Lock(docID)
	defer docWriteMtx.Unlock(docID)

	// Register the rollback after acquiring the lock so cleanup runs while the
	// lock is still held (defers are LIFO). Otherwise the unlock would fire
	// first and a concurrent writer could chain a new version off the
	// half-written one this call is about to remove.
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
	// See CreateDocument: a panic must reach the rollback above as an error.
	defer errs.RecoverPanicAsError(&err)

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
	if err = result.Validate(); err != nil {
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
		ctx,
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

	if versionInfo.ChangesNothing(prevVersionInfo, companyID) {
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
	}

	versionInfo.Files, err = versionDirFileInfos(ctx, versionDir)
	if err != nil {
		return nil, err
	}
	if len(versionInfo.Files) == 0 {
		// Every version must contain at least one file: a document cannot start
		// with, or be reduced to, an empty change-less version, and
		// HashedDocument.Validate rejects one — a document with such a version
		// can never be backed up, synced or restored again.
		//
		// Checked here rather than at each call site because this is where a
		// version's file set is established, and it is not the set the caller
		// passed: the directory is enumerated through docdb.DirFileProvider,
		// which does not report hidden entries or sub-directories as files of a
		// version. A caller that wrote only such entries ends up with an empty
		// set however many files it handed over, which is how CreateDocument
		// used to create a document tracking nothing and RestoreDocument used
		// to restore a version reading back empty.
		return nil, errs.Errorf("document %s version %s has no files: every version must contain at least one file", docID, version)
	}

	// A nil prevVersionFiles for the first version of a document
	// makes SetFileDeltas report all files as added.
	//
	// TODO: this re-reads and content-hashes every file of the previous version
	// although the callers already hold those hashes. AddDocumentVersion parsed
	// <prev>.json into prevVersionInfo.Files, and RestoreDocument has the
	// backup's FileHashes, both of which carry exactly the name/hash pairs
	// SetFileDeltas compares — so committing a one-line change to a 200 MB
	// version reads and hashes 400 MB instead of 200 MB. Passing the previous
	// file set in instead of the directory would remove the second read; it is
	// left as is here because it changes newVersionInfo's signature and its
	// prevVersion/prevVersionDir invariant, which is more than this release's
	// correctness fixes should touch.
	var prevVersionFiles map[string]docdb.FileInfo
	if prevVersionDir != "" {
		prevVersionFiles, err = versionDirFileInfos(ctx, prevVersionDir)
		if err != nil {
			return nil, err
		}
	}
	versionInfo.SetFileDeltas(prevVersionFiles)

	return versionInfo, nil
}

// versionDirFileInfos reads the FileInfos of the files in a version directory
// keyed by filename.
//
// It enumerates the directory with docdb.DirFileProvider so that a version's
// metadata describes exactly the files a reader of that version will get:
// entries the provider hides (hidden files, sub-directories) must not end up
// in Files, and must not be reported as removed when they are only present in
// the previous version's directory.
func versionDirFileInfos(ctx context.Context, versionDir fs.File) (map[string]docdb.FileInfo, error) {
	filenames, err := docdb.DirFileProvider(versionDir).ListFiles(ctx)
	if err != nil {
		return nil, err
	}
	fileInfos := make(map[string]docdb.FileInfo, len(filenames))
	for _, filename := range filenames {
		fileInfos[filename], err = docdb.ReadFileInfo(ctx, versionDir.Join(filename))
		if err != nil {
			return nil, err
		}
	}
	return fileInfos, nil
}

func (c *Conn) RestoreDocument(ctx context.Context, doc *docdb.HashedDocument, recreate bool) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, doc, recreate)

	if err = ctx.Err(); err != nil {
		return err
	}
	if err = doc.Validate(); err != nil {
		return err
	}

	docWriteMtx.Lock(doc.ID)
	defer docWriteMtx.Unlock(doc.ID)

	docDir := c.documentDir(doc.ID)

	if recreate && docDir.Exists() {
		// NOTE: recreate deletes the existing document before the replacement
		// is written and is therefore not atomic — a later failure in this call
		// leaves the document absent (the rollback below only undoes what this
		// call created, not this up-front delete). See Conn.RestoreDocument.
		//
		// Surface a failure to read the current company instead of swallowing
		// it: without the company we cannot remove the old company-document
		// marker, so proceeding would leave a stale mapping behind.
		currCompanyID, e := c.documentCompanyID(ctx, doc.ID)
		if e != nil {
			return e
		}
		e = uuiddir.Remove(c.companiesDir.Join(currCompanyID.String()), doc.ID)
		if e != nil {
			return e
		}
		e = uuiddir.RemoveDir(c.documentsDir, docDir)
		if e != nil {
			return e
		}
	}

	docExisted := docDir.Exists()

	var (
		existingVersions []docdb.VersionTime
		prevVersion      *docdb.VersionTime
		prevVersionDir   fs.File
	)

	if docExisted {
		currCompanyID, err := c.documentCompanyID(ctx, doc.ID)
		if err != nil {
			return err
		}
		existingVersions, err = c.documentVersions(ctx, doc.ID)
		if err != nil {
			return err
		}
		// Compared against the company the backup names for the latest version
		// on disk, not against the backup's current company, so a backup whose
		// newer versions move the document to another company restores that
		// move instead of being refused as a mismatch.
		err = docdb.CheckRestoreCompanyID(doc, existingVersions, currCompanyID)
		if err != nil {
			return err
		}
		// prevVersion/prevVersionDir are intentionally left nil/empty here.
		// VersionTimes() is ascending and the loop below sets the predecessor
		// as it walks (both for skipped existing versions and newly written
		// ones), so the earliest missing version is correctly diffed against
		// its real predecessor (or none) rather than the latest on-disk version.
	} else {
		err = docDir.MakeAllDirs()
		if err != nil {
			return err
		}
		err = docDir.Join("company.id").WriteAll(doc.CompanyID.StringBytes())
		if err != nil {
			return err
		}
		err = c.makeCompanyDocumentDir(doc.CompanyID, doc.ID)
		if err != nil {
			return err
		}
	}

	var (
		createdVersionDirs []fs.File
		createdInfoFiles   []fs.File
		relinkedInfoFiles  []relinkedInfoFile
		// relinkedInfoFileSaved keeps the rollback from saving the same info
		// file twice, which would put back what this call wrote rather than
		// what the file held before it.
		relinkedInfoFileSaved = make(map[fs.File]bool)
	)
	defer func() {
		if err == nil {
			return
		}
		for _, d := range createdVersionDirs {
			err = errors.Join(err, d.RemoveRecursive())
		}
		for _, f := range createdInfoFiles {
			if f.Exists() {
				err = errors.Join(err, f.Remove())
			}
		}
		// A relinked successor is a version this call did not create and must
		// not remove, so its original bytes are written back instead.
		for _, r := range relinkedInfoFiles {
			err = errors.Join(err, r.file.WriteAll(r.data))
		}
		if !docExisted {
			err = errors.Join(err, c.removeCompanyDocumentDirIfExists(doc.CompanyID, doc.ID))
			if docDir.Exists() {
				err = errors.Join(err, uuiddir.RemoveDir(c.documentsDir, docDir))
			}
		}
	}()

	// latestWritten is the newest version this call wrote, which the ascending
	// walk below leaves at the last one it wrote. It decides whether the
	// company marker has to be re-derived at the end.
	var latestWritten *docdb.VersionTime

	versionTimes := doc.VersionTimes()
	existingVersionSet := versionTimeSet(existingVersions)
	for i, v := range versionTimes {
		if !recreate && existingVersionSet[v] {
			prevVersion = &v
			prevVersionDir = docDir.Join(v.String())
			continue
		}

		versionDir := docDir.Join(v.String())
		err = versionDir.MakeDir()
		if err != nil {
			return err
		}
		createdVersionDirs = append(createdVersionDirs, versionDir)

		hv := doc.Versions[v]
		for filename, hash := range hv.FileHashes {
			if err = versionDir.Join(filename).WriteAllContext(ctx, doc.HashedFiles[hash]); err != nil {
				return err
			}
		}

		// Every version is written with the company of that version, so a
		// document moved between companies keeps its move history instead of
		// having every version filed under its current company.
		versionInfo, viErr := newVersionInfo(
			ctx,
			doc.VersionCompanyID(v),
			doc.ID,
			v,
			prevVersion,
			hv.CommitUserID,
			hv.CommitReason,
			versionDir,
			prevVersionDir,
		)
		if viErr != nil {
			return viErr
		}

		infoFile := docDir.Joinf("%s.json", v)
		if err = versionInfo.WriteJSON(infoFile); err != nil {
			return err
		}
		createdInfoFiles = append(createdInfoFiles, infoFile)

		// A version written back into the middle of an existing chain has to
		// take back the successor that DeleteDocumentVersion relinked to this
		// version's own predecessor when it was removed. Only a version of the
		// backup is ever taken over, and only while it still chains off that
		// same predecessor, which is the rule storeconn restores by (see
		// storeconn.CreateDocumentVersionInput.RelinkSuccessor): no property of
		// a stored version identifies it as this one's successor, and a version
		// the destination has but the backup does not is kept as-is rather than
		// adopted.
		//
		// The successor to take back is the backup's next version that the
		// destination actually holds, not simply the next one in the backup.
		// Two adjacent missing versions otherwise name one that is not there
		// yet: nothing is relinked, and the version that does chain off the
		// predecessor stays on it — restoring v1 and v2 into a destination
		// holding v0 and v3 of v0→v1→v2→v3 named the absent v2 while filling
		// v1 in, left v3 on v0 and forked the chain. Scanning forward relinks
		// v3 onto v1 and then onto v2 as each of them is filled in, the same
		// way storeconn's merge-restore does.
		if !recreate {
			for j := i + 1; j < len(versionTimes); j++ {
				if !existingVersionSet[versionTimes[j]] {
					continue
				}
				var relinked *relinkedInfoFile
				relinked, err = relinkSuccessorInfoFile(ctx, docDir, doc.ID, versionTimes[j], prevVersion, v)
				if err != nil {
					return err
				}
				// Only the content from before this call can undo it: a
				// successor that a run of restored versions is filled in front
				// of is rewritten once per version, and every rewrite but the
				// first saves what an earlier one of them wrote.
				if relinked != nil && !relinkedInfoFileSaved[relinked.file] {
					relinkedInfoFileSaved[relinked.file] = true
					relinkedInfoFiles = append(relinkedInfoFiles, *relinked)
				}
				break
			}
		}

		prevVersion = &v
		prevVersionDir = versionDir
		latestWritten = &v
	}

	// The document belongs to the company of its latest version, which merging
	// a backup into an existing document can move: its newer versions can be
	// the ones that moved the document, leaving the company marker naming the
	// company from before the move. Only the merge path needs this — a document
	// created by this call had its marker written as doc.CompanyID above, which
	// doc.Validate() requires to be the company of the backup's latest version.
	//
	// Gated on this call having written the version that is now the document's
	// latest one. A merge that wrote nothing, or only versions below the latest
	// one on disk, changed nothing about who owns the document, and re-deriving
	// the company from the latest version would then overwrite a marker that
	// SetDocumentCompanyID moved without committing a version: that marker
	// names a company no version names, on purpose, and ReadHashedDocument
	// documents it as the answer that wins. Reverting it on every merge made
	// every incremental sync into this store undo every such move.
	//
	// Done as the last step, after which nothing can fail, because the deferred
	// rollback above only removes the versions and files this call created, not
	// a company re-assignment.
	if docExisted && latestWritten != nil {
		latestVersionInfo, _, err := c.latestDocumentVersionInfo(ctx, doc.ID)
		if err != nil {
			return err
		}
		if latestVersionInfo.Version.Equal(*latestWritten) {
			return c.setDocumentCompanyID(ctx, doc.ID, latestVersionInfo.CompanyID)
		}
	}
	return nil
}

// relinkedInfoFile is the original content of a version info file that
// RestoreDocument rewrote to relink a chain, kept so the rollback can put the
// file back as it was.
type relinkedInfoFile struct {
	file fs.File
	data []byte
}

// relinkSuccessorInfoFile makes successor name newVersion as its predecessor,
// but only while it still names prevVersion. It returns the file's original
// content so the caller can undo the rewrite, or nil when nothing was
// rewritten.
//
// Both callers hand a successor from one predecessor to another: RestoreDocument
// gives it to the version it fills in front of it, and DeleteDocumentVersion
// gives it to the deleted version's own predecessor. A successor that names
// something else is not the row either of them may move: it never chained off
// prevVersion or was already relinked, and taking it over would leave it naming
// a predecessor whose file set it never derived from. A nil prevVersion relinks
// nothing — for a restore that is the earliest version of the backup, which had
// no predecessor to be filled in after.
//
// Only PrevVersion is rewritten. The successor's added/modified/removed lists
// still describe its diff against the version it used to chain off, which is
// what storeconn's relink leaves behind as well — the two stores stay
// equivalent, rather than one of them silently deriving different change lists
// for the same restore.
func relinkSuccessorInfoFile(ctx context.Context, docDir fs.File, docID uu.ID, successor docdb.VersionTime, prevVersion *docdb.VersionTime, newVersion docdb.VersionTime) (relinked *relinkedInfoFile, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docDir, docID, successor, prevVersion, newVersion)

	if prevVersion == nil {
		return nil, nil
	}
	infoFile := docDir.Joinf("%s.json", successor)
	if !infoFile.Exists() {
		return nil, nil
	}
	// The original content is kept for the rollback, so the VersionInfo is
	// decoded from those same bytes rather than reading the file a second time.
	original, err := infoFile.ReadAll()
	if err != nil {
		return nil, err
	}
	versionInfo, legacyFormat, err := unmarshalVersionInfoJSON(original)
	if err != nil {
		return nil, err
	}
	if legacyFormat {
		log.Info("Loading old VersionInfo format").Str("file", string(infoFile)).Log()
	}
	if versionInfo.PrevVersion == nil || !versionInfo.PrevVersion.Equal(*prevVersion) {
		return nil, nil
	}
	versionInfo.PrevVersion = &newVersion
	if err = versionInfo.WriteJSON(infoFile); err != nil {
		return nil, err
	}
	return &relinkedInfoFile{file: infoFile, data: original}, nil
}

// relinkSuccessorsOfDeletedVersion chains every remaining version that names
// deletedVersion as its predecessor onto prevVersion, which is the predecessor
// deletedVersion itself named.
//
// Successors are found by the predecessor they name rather than by their place
// in the version order, which is how pgstore finds them too (`where
// prev_version = <deleted version>`): a version naming anything else is not a
// successor of the deleted one and keeps the predecessor its file set was
// derived from. Every match is relinked rather than only the first one found,
// because localfsdb has no index that refuses two versions naming the same
// predecessor, so a document can hold more than one of them.
func relinkSuccessorsOfDeletedVersion(ctx context.Context, docDir fs.File, docID uu.ID, deletedVersion, prevVersion docdb.VersionTime) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docDir, docID, deletedVersion, prevVersion)

	var versions []docdb.VersionTime
	err = enumVersionDirs(ctx, docDir, docID, func(version docdb.VersionTime, _ fs.File) {
		versions = append(versions, version)
	})
	if err != nil {
		return err
	}
	for _, version := range versions {
		// The original content is only needed by a caller that can roll its
		// rewrite back, which a delete cannot: the version it would relink the
		// successor to is already gone.
		_, err = relinkSuccessorInfoFile(ctx, docDir, docID, version, &deletedVersion, prevVersion)
		if err != nil {
			return err
		}
	}
	return nil
}

// versionTimeSet returns versions as a set for membership tests, so the restore
// walk below does not scan the whole slice once per version.
func versionTimeSet(versions []docdb.VersionTime) map[docdb.VersionTime]bool {
	set := make(map[docdb.VersionTime]bool, len(versions))
	for _, v := range versions {
		set[v] = true
	}
	return set
}

// readAndFixVersionInfoJSON reads a VersionInfo from a JSON file.
// It handles a legacy format where ModifiedFiles was misspelled as "ModidfiedFiles".
// If writeFixedVersion is true and the legacy field is found, the file is rewritten
// with the corrected field name.
func readAndFixVersionInfoJSON(ctx context.Context, file fs.File, writeFixedVersion bool) (versionInfo *docdb.VersionInfo, err error) {
	data, err := file.ReadAllContext(ctx)
	if err != nil {
		return nil, err
	}
	versionInfo, legacyFormat, err := unmarshalVersionInfoJSON(data)
	if err != nil {
		return nil, err
	}
	if legacyFormat {
		if writeFixedVersion {
			log.Info("Fixing old VersionInfo format").Str("file", string(file)).Log()
			err = versionInfo.WriteJSON(file)
			if err != nil {
				return nil, err
			}
		} else {
			log.Info("Loading old VersionInfo format").Str("file", string(file)).Log()
		}
	}
	return versionInfo, nil
}

// unmarshalVersionInfoJSON decodes a VersionInfo from the JSON content of a
// version info file, reporting whether it was in the legacy format where
// ModifiedFiles was misspelled as "ModidfiedFiles". Decoding is separate from
// reading so a caller that already holds the bytes does not read the file twice.
func unmarshalVersionInfoJSON(data []byte) (versionInfo *docdb.VersionInfo, legacyFormat bool, err error) {
	var i struct {
		docdb.VersionInfo
		ModidfiedFiles []string // with typo
	}
	err = json.Unmarshal(data, &i)
	if err != nil {
		return nil, false, fmt.Errorf("%w because: %w", fs.ErrUnmarshalJSON, err)
	}
	if len(i.ModidfiedFiles) > 0 && len(i.ModifiedFiles) == 0 {
		i.ModifiedFiles = i.ModidfiedFiles
		return &i.VersionInfo, true, nil
	}
	return &i.VersionInfo, false, nil
}
