package docdb

import (
	"context"
	"errors"
	"fmt"

	"github.com/ungerik/go-fs"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

func NewConn(
	documentStore DocumentStore,
	metadataStore MetadataStore,
) Conn {
	return &conn{
		documentStore: documentStore,
		metadataStore: metadataStore,
	}
}

// Callbacks
type (
	// CreateVersionResult is the result of a CreateVersionFunc callback.
	// It contains the files to write in the new version,
	// the filenames to remove from the previous version,
	// and the optional new company ID to change which company the document belongs to.
	// The new version timestamp must be after the previous version timestamp.
	CreateVersionResult struct {
		Version      VersionTime     // Timestamp of the new version which must be after previous version timestamp
		WriteFiles   []fs.FileReader // Files to write in the new version
		RemoveFiles  []string        // Filenames to remove from the previous version (if any)
		NewCompanyID uu.NullableID   // Optional new company ID to change which company the document belongs to (null to keep previous company)
	}

	// CreateVersionFunc is a callback function used to create a new document version
	// based on the previous version.
	//
	// It receives the previous version timestamp and a FileProvider for accessing
	// the files from the previous version.
	//
	// If this function returns an error or panics, the entire version creation
	// is atomically rolled back.
	CreateVersionFunc func(ctx context.Context, docID uu.ID, prevVersion VersionTime, prevFiles FileProvider) (*CreateVersionResult, error)

	// OnNewVersionFunc is a callback function invoked after a new document version
	// has been created but before it is committed.
	//
	// It receives the VersionInfo for the newly created version and can perform
	// validation or side effects.
	//
	// If this function returns an error or panics, the entire document/version creation
	// is atomically rolled back, preventing the new version from being committed.
	// This allows the callback to act as a validation gate or to ensure related
	// operations complete successfully before committing the new version.
	OnNewVersionFunc func(ctx context.Context, versionInfo *VersionInfo) error
)

// CreateVersionWriteFiles returns a CreateVersionFunc callback that adds or
// overwrites files in the document without removing any existing files.
//
// This is a convenience function for the common case of adding new files
// or replacing existing files in a document version. It automatically
// generates a new version timestamp using NewVersionTime().
//
// The provided files will be written to the new version. If a file with
// the same name already exists in the previous version, it will be overwritten.
// All other files from the previous version are preserved.
//
// Usage with AddDocumentVersion to add a new file:
//
//	newFile := fs.NewMemFile("attachment.pdf", pdfData)
//	err := conn.AddDocumentVersion(ctx, docID, userID, "added attachment",
//	    docdb.CreateVersionWriteFiles(newFile),
//	    docdb.CaptureNewVersionInfo(&versionInfo))
//
// Usage to replace an existing file:
//
//	updatedFile := fs.NewMemFile("invoice.pdf", newPdfData)
//	err := conn.AddDocumentVersion(ctx, docID, userID, "replaced invoice",
//	    docdb.CreateVersionWriteFiles(updatedFile),
//	    docdb.CaptureNewVersionInfo(&versionInfo))
//
// Usage to add multiple files at once:
//
//	err := conn.AddDocumentVersion(ctx, docID, userID, "added multiple files",
//	    docdb.CreateVersionWriteFiles(file1, file2, file3),
//	    docdb.CaptureNewVersionInfo(&versionInfo))
//
// For more complex operations (removing files, changing company ID, or using
// a specific version timestamp), implement CreateVersionFunc directly.
func CreateVersionWriteFiles(writeFiles ...fs.FileReader) CreateVersionFunc {
	return func(ctx context.Context, docID uu.ID, prevVersion VersionTime, prevFiles FileProvider) (*CreateVersionResult, error) {
		return &CreateVersionResult{
			Version:    NewVersionTime(),
			WriteFiles: writeFiles,
		}, nil
	}
}

// CreateVersionRemoveFiles returns a CreateVersionFunc callback that removes
// files from the document without adding any new files.
//
// This is a convenience function for the common case of removing files
// from a document version. It automatically generates a new version
// timestamp using NewVersionTime().
//
// The specified filenames will be removed from the new version.
// All other files from the previous version are preserved.
//
// Usage with AddDocumentVersion to remove a single file:
//
//	err := conn.AddDocumentVersion(ctx, docID, userID, "removed attachment",
//	    docdb.CreateVersionRemoveFiles("attachment.pdf"),
//	    docdb.CaptureNewVersionInfo(&versionInfo))
//
// Usage to remove multiple files at once:
//
//	err := conn.AddDocumentVersion(ctx, docID, userID, "cleanup old files",
//	    docdb.CreateVersionRemoveFiles("old1.pdf", "old2.pdf", "temp.txt"),
//	    docdb.CaptureNewVersionInfo(&versionInfo))
//
// Note: Removing all files from a document will result in an empty version.
// Consider using DeleteDocument if you want to remove the document entirely.
//
// For more complex operations (adding files while removing others, changing
// company ID, or using a specific version timestamp), implement
// CreateVersionFunc directly.
func CreateVersionRemoveFiles(removeFiles ...string) CreateVersionFunc {
	return func(ctx context.Context, docID uu.ID, prevVersion VersionTime, prevFiles FileProvider) (*CreateVersionResult, error) {
		return &CreateVersionResult{
			Version:     NewVersionTime(),
			RemoveFiles: removeFiles,
		}, nil
	}
}

// CaptureNewVersionInfo returns an OnNewVersionFunc callback that captures
// the VersionInfo of a newly created document version into the provided pointer.
//
// This is useful when you need to retrieve the VersionInfo after calling
// CreateDocument or AddDocumentVersion, as these methods don't return it directly.
//
// Usage with CreateDocument:
//
//	var versionInfo *docdb.VersionInfo
//	err := conn.CreateDocument(ctx, companyID, docID, userID, "initial upload",
//	    docdb.NewVersionTime(), files, docdb.CaptureNewVersionInfo(&versionInfo))
//	if err != nil {
//	    return err
//	}
//	// versionInfo now contains the created version's metadata
//	fmt.Println("Created version:", versionInfo.Version)
//
// Usage with AddDocumentVersion:
//
//	var versionInfo *docdb.VersionInfo
//	err := conn.AddDocumentVersion(ctx, docID, userID, "added attachment",
//	    docdb.CreateVersionWriteFiles(newFile),
//	    docdb.CaptureNewVersionInfo(&versionInfo))
//	if err != nil {
//	    return err
//	}
//	// versionInfo now contains the new version's metadata
func CaptureNewVersionInfo(out **VersionInfo) OnNewVersionFunc {
	return func(ctx context.Context, versionInfo *VersionInfo) error {
		if out == nil {
			return errs.New("nil output pointer passed to CaptureNewVersionInfo")
		}
		*out = versionInfo
		return nil
	}
}

// Conn is an interface for a docdb connection.
type Conn interface {
	// DocumentExists returns true if a document with the passed docID exists
	DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error)

	// EnumDocumentIDs calls the passed callback with the ID of every document in the database
	EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error

	// EnumCompanyDocumentIDs calls the passed callback with the ID of every document of a company in the database
	EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error

	// DocumentCompanyID returns the companyID for a docID
	DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error)

	// SetDocumentCompanyID changes the companyID for a document
	SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error

	// DocumentVersions returns all version timestamps of a document in ascending order.
	// Returns nil and no error if the document does not exist or has no versions.
	DocumentVersions(ctx context.Context, docID uu.ID) ([]VersionTime, error)

	// LatestDocumentVersion returns the latest VersionTime of a document
	LatestDocumentVersion(ctx context.Context, docID uu.ID) (VersionTime, error)

	// DocumentVersionInfo returns the VersionInfo for a VersionTime
	DocumentVersionInfo(ctx context.Context, docID uu.ID, version VersionTime) (*VersionInfo, error)

	// LatestDocumentVersionInfo returns the VersionInfo for the latest document version
	LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*VersionInfo, error)

	// DocumentVersionFileProvider returns a FileProvider for the files of a document version
	DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version VersionTime) (FileProvider, error)

	// ReadDocumentVersionFile returns the contents of a file of a document version.
	// Wrapped ErrDocumentNotFound, ErrDocumentVersionNotFound, ErrDocumentFileNotFound
	// will be returned in case of such error conditions.
	ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version VersionTime, filename string) (data []byte, err error)

	// DeleteDocument deletes all versions and stored files of a document.
	// Returns wrapped ErrDocumentNotFound in case the document does not exist.
	DeleteDocument(ctx context.Context, docID uu.ID) error

	// DeleteDocumentVersion deletes a version of a document
	// and returns the left over versions.
	// If the version is the only version of the document,
	// then the document will be deleted and no leftVersions are returned.
	// Returns wrapped ErrDocumentNotFound and ErrDocumentVersionNotFound
	// in case of such error conditions.
	// DeleteDocumentVersion should not be used for normal docdb operations,
	// just to clean up mistakes or sync database states.
	DeleteDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) (leftVersions []VersionTime, err error)

	// CreateDocument creates a new document with the provided files.
	// The document is created with companyID, docID, and userID as metadata,
	// and reason describes why the document is being created.
	//
	// The passed version time is the timestamp of the new version.
	//
	// After the document version is created but before it is committed,
	// the onNewVersion callback is called with the resulting VersionInfo.
	// If onNewVersion returns an error or panics, the entire document creation
	// is atomically rolled back, the error is returned, or the panic is propagated.
	// onNewVersion must not be nil.
	//
	// Returns ErrDocumentAlreadyExists if a document with docID already exists.
	CreateDocument(ctx context.Context, companyID, docID, userID uu.ID, reason string, version VersionTime, files []fs.FileReader, onNewVersion OnNewVersionFunc) error

	// AddDocumentVersion adds a new version to an existing document.
	// The createVersion callback is invoked with the previous version info
	// and should return the files to write, files to remove, and optionally
	// a changed company ID for the document (nil to keep current).
	//
	// After the new version is created but before it is committed,
	// the onNewVersion callback is called with the resulting VersionInfo.
	// If createVersion or onNewVersion returns an error or panics,
	// the entire version creation is atomically rolled back,
	// the error is returned, or the panic is propagated.
	// createVersion and onNewVersion must not be nil.
	//
	// Returns wrapped ErrDocumentNotFound if the document does not exist.
	// Returns wrapped ErrNoChanges if the new version has identical files
	// compared to the previous version.
	AddDocumentVersion(ctx context.Context, docID, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) error

	// AddMultiDocumentVersion adds a new version to multiple existing documents as atomic operation.
	// See AddDocumentVersion for details on the callbacks and error handling.
	// Documents with no file changes are skipped (ErrNoChanges per-doc is not an error).
	// Returns wrapped ErrNoChanges only if no document was changed at all.
	AddMultiDocumentVersion(ctx context.Context, docIDs uu.IDSlice, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) error

	// RestoreDocument
	RestoreDocument(ctx context.Context, doc *HashedDocument, merge bool) error
}

// type DebugFileAccessConn interface {
// 	Conn

// 	DebugGetDocumentDir(docID uu.ID) fs.File
// 	DebugGetDocumentVersionFile(docID uu.ID, version VersionTime, filename string) (fs.File, error)
// }

type conn struct {
	documentStore DocumentStore
	metadataStore MetadataStore
}

func (c *conn) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	return c.documentStore.DocumentExists(ctx, docID)
}

func (c *conn) EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error {
	return c.documentStore.EnumDocumentIDs(ctx, callback)
}

func (c *conn) DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version VersionTime) (FileProvider, error) {
	versionInfo, err := c.metadataStore.DocumentVersionInfo(ctx, docID, version)
	if err != nil {
		return nil, err
	}

	hashes := []string{}
	for _, item := range versionInfo.Files {
		hashes = append(hashes, item.Hash)
	}

	return c.documentStore.DocumentHashFileProvider(ctx, docID, hashes)
}

func (c *conn) ReadDocumentVersionFile(ctx context.Context, docID uu.ID, version VersionTime, filename string) (data []byte, err error) {
	versionInfo, err := c.metadataStore.DocumentVersionInfo(ctx, docID, version)
	if err != nil {
		return nil, err
	}

	fileInfo, ok := versionInfo.Files[filename]
	if !ok {
		return nil, NewErrDocumentFileNotFound(docID, filename)
	}

	return c.documentStore.ReadDocumentHashFile(ctx, docID, filename, fileInfo.Hash)
}

func (c *conn) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	return c.metadataStore.DocumentCompanyID(ctx, docID)
}

func (c *conn) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error {
	return c.metadataStore.SetDocumentCompanyID(ctx, docID, companyID)
}

func (c *conn) DocumentVersions(ctx context.Context, docID uu.ID) ([]VersionTime, error) {
	return c.metadataStore.DocumentVersions(ctx, docID)
}

func (c *conn) LatestDocumentVersion(ctx context.Context, docID uu.ID) (VersionTime, error) {
	return c.metadataStore.LatestDocumentVersion(ctx, docID)
}

func (c *conn) EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error {
	return c.metadataStore.EnumCompanyDocumentIDs(ctx, companyID, callback)
}

func (c *conn) DocumentVersionInfo(ctx context.Context, docID uu.ID, version VersionTime) (*VersionInfo, error) {
	return c.metadataStore.DocumentVersionInfo(ctx, docID, version)
}

func (c *conn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*VersionInfo, error) {
	return c.metadataStore.LatestDocumentVersionInfo(ctx, docID)
}

func (c *conn) DeleteDocument(ctx context.Context, docID uu.ID) error {
	if err := c.metadataStore.DeleteDocument(ctx, docID); err != nil {
		return err
	}

	if err := c.documentStore.DeleteDocument(ctx, docID); err != nil {
		return err
	}

	return nil
}

func (c *conn) DeleteDocumentVersion(ctx context.Context, docID uu.ID, version VersionTime) (leftVersions []VersionTime, err error) {
	leftVersions, hashesToDelete, err := c.metadataStore.DeleteDocumentVersion(ctx, docID, version)

	if err != nil {
		return nil, err
	}

	if err = c.documentStore.DeleteDocumentHashes(ctx, docID, hashesToDelete); err != nil {
		return nil, err
	}

	return leftVersions, err
}

func (c *conn) CreateDocument(
	ctx context.Context,
	companyID,
	docID,
	userID uu.ID,
	reason string,
	version VersionTime,
	files []fs.FileReader,
	onNewVersion OnNewVersionFunc,
) error {
	return c.createDocumentVersion(ctx, companyID, docID, userID, reason, version, files, onNewVersion)
}

func (c *conn) createDocumentVersion(
	ctx context.Context,
	companyID,
	docID,
	userID uu.ID,
	reason string,
	version VersionTime,
	files []fs.FileReader,
	onNewVersion OnNewVersionFunc,
) (err error) {
	if err := version.Validate(); err != nil {
		return err
	}
	if onNewVersion == nil {
		return errs.New("nil onNewVersion func passed to createDocumentVersion")
	}

	var versionInfo *VersionInfo

	defer func() {
		errs.RecoverPanicAsErrorWithFuncParams(&err, ctx, companyID, docID, userID, reason, version, files, onNewVersion)
		if err != nil {
			if versionInfo != nil {
				hashes := []string{}
				for _, item := range versionInfo.Files {
					hashes = append(hashes, item.Hash)
				}
				err = errors.Join(err, c.documentStore.DeleteDocumentHashes(ctx, docID, hashes))
			}
			err = errors.Join(err, c.metadataStore.DeleteDocument(ctx, docID))
		}
	}()

	err = c.documentStore.CreateDocument(ctx, docID, version, files)
	if err != nil {
		return err
	}

	versionInfo, err = c.metadataStore.CreateDocument(ctx, companyID, docID, userID, reason, version, files)
	if err != nil {
		return err
	}

	return onNewVersion(ctx, versionInfo)
}

func (c *conn) AddDocumentVersion(
	ctx context.Context,
	docID,
	userID uu.ID,
	reason string,
	createVersion CreateVersionFunc,
	onNewVersion OnNewVersionFunc,
) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, docID, userID, reason, createVersion, onNewVersion)

	for _, check := range []func() error{ctx.Err, docID.Validate, userID.Validate} {
		if err := check(); err != nil {
			return err
		}
	}
	if createVersion == nil {
		return errs.New("nil createVersion func passed to AddDocumentVersion")
	}
	if onNewVersion == nil {
		return errs.New("nil onNewVersion func passed to AddDocumentVersion")
	}

	latestVersionInfo, err := c.metadataStore.LatestDocumentVersionInfo(ctx, docID)
	if err != nil {
		return err
	}

	hashes := []string{}
	for _, file := range latestVersionInfo.Files {
		hashes = append(hashes, file.Hash)
	}

	fileProvider, err := c.documentStore.DocumentHashFileProvider(ctx, docID, hashes)
	if err != nil {
		return err
	}

	result, err := safelyCallCreateVersionFunc(
		ctx,
		docID,
		latestVersionInfo.Version,
		fileProvider,
		createVersion,
	)
	if err != nil {
		return err
	}
	if err := result.Version.Validate(); err != nil {
		return errs.Errorf("version returned from CreateVersionFunc: %w", err)
	}
	if !result.Version.After(latestVersionInfo.Version) {
		return errs.Errorf("version %s returned from CreateVersionFunc is not after previous version %s", result.Version, latestVersionInfo.Version)
	}

	companyID := result.NewCompanyID.GetOr(latestVersionInfo.CompanyID)

	addedFiles := []*FileInfo{}
	modifiedFiles := []*FileInfo{}

	for _, file := range result.WriteFiles {
		data, err := file.ReadAll()
		if err != nil {
			return err
		}

		fileInfo := &FileInfo{Name: file.Name(), Size: file.Size(), Hash: ContentHash(data)}
		if fileExists, _ := fileProvider.HasFile(file.Name()); fileExists {
			modifiedFiles = append(modifiedFiles, fileInfo)
		} else {
			addedFiles = append(addedFiles, fileInfo)
		}
	}

	newVersionInfo, err := c.metadataStore.AddDocumentVersion(
		ctx,
		result.Version,
		latestVersionInfo.Version,
		docID,
		companyID,
		userID,
		reason,
		addedFiles,
		modifiedFiles,
		result.RemoveFiles,
	)

	if err != nil {
		return err
	}

	if err := c.documentStore.CreateDocument(ctx, docID, result.Version, result.WriteFiles); err != nil {
		return err
	}

	safeOnNewVersion := func() (err error) {
		defer errs.RecoverPanicAsError(&err)
		return onNewVersion(ctx, newVersionInfo)
	}

	err = safeOnNewVersion()
	if err == nil {
		return nil
	}

	_, _, pgCleanupErr := c.metadataStore.DeleteDocumentVersion(ctx, docID, result.Version)
	if pgCleanupErr != nil {
		err = errors.Join(err, pgCleanupErr)
	}

	hashesToDelete := []string{}
	for _, f := range addedFiles {
		hashesToDelete = append(hashesToDelete, f.Hash)
	}

	for _, f := range modifiedFiles {
		hashesToDelete = append(hashesToDelete, f.Hash)
	}

	if s3Err := c.documentStore.DeleteDocumentHashes(ctx, docID, hashesToDelete); s3Err != nil {
		err = errors.Join(err, s3Err)
	}

	return err
}

func (c *conn) AddMultiDocumentVersion(ctx context.Context, docIDs uu.IDSlice, userID uu.ID, reason string, createVersion CreateVersionFunc, onNewVersion OnNewVersionFunc) error {
	return AddMultiDocumentVersionImpl(ctx, c, docIDs, userID, reason, createVersion, onNewVersion)
}

func (c *conn) RestoreDocument(ctx context.Context, doc *HashedDocument, merge bool) error {
	return ErrNotImplemented
}

func safelyCallCreateVersionFunc(
	ctx context.Context,
	docID uu.ID,
	prevVersion VersionTime,
	prevFiles FileProvider,
	createVersion CreateVersionFunc,
) (result *CreateVersionResult, err error) {
	defer errs.RecoverPanicAsError(&err)

	return createVersion(ctx, docID, prevVersion, prevFiles)
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
					err = errors.Join(err, fmt.Errorf("failed to undo new document version of atomic multi-document operation: %w", deleteErr))
				}
			}
		}
	}()

	for _, docID := range docIDs {
		err = conn.AddDocumentVersion(ctx, docID, userID, reason, createVersion, func(ctx context.Context, versionInfo *VersionInfo) error {
			err := onNewVersion(ctx, versionInfo)
			if err == nil {
				created = append(created, createdVersion{
					docID:   versionInfo.DocID,
					version: versionInfo.Version,
				})
			}
			return err
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
