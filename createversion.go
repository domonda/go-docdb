package docdb

import (
	"context"
	"slices"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
)

// Callbacks
type (
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

// CreateVersionResult is the result of a CreateVersionFunc callback.
// It contains the files to write in the new version,
// the filenames to remove from the previous version,
// and the optional new company ID to change which company the document belongs to.
// The new version timestamp must be after the previous version timestamp.
//
// A filename must not appear in both WriteFiles and RemoveFiles.
// If an existing file should be rewritten, only add it to WriteFiles;
// there is no need to remove it first via RemoveFiles.
type CreateVersionResult struct {
	Version      VersionTime     // Timestamp of the new version which must be after previous version timestamp
	WriteFiles   []fs.FileReader // Files to write in the new version (also used to overwrite existing files)
	RemoveFiles  []string        // Filenames to remove from the previous version (if any)
	NewCompanyID uu.NullableID   // Optional new company ID to change which company the document belongs to (null to keep previous company)
}

// Validate returns an error if the CreateVersionResult is invalid.
// It checks that the version timestamp is not null,
// that all WriteFiles exist,
// and that no filename appears in both WriteFiles and RemoveFiles.
func (r *CreateVersionResult) Validate() error {
	if r.Version.IsNull() {
		return errs.New("CreateVersionResult.Version is null")
	}
	for _, wf := range r.WriteFiles {
		if wf == nil || !wf.Exists() {
			return errs.Errorf("CreateVersionResult.WriteFiles entry does not exist: %#v", wf)
		}
		if slices.Contains(r.RemoveFiles, wf.Name()) {
			return errs.Errorf(
				"filename %q in both WriteFiles and RemoveFiles of CreateVersionResult",
				wf.Name(),
			)
		}
	}
	return nil
}

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
