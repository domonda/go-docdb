package docdb

import (
	"database/sql"
	"fmt"
	"os"
	"time"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

const (
	// ErrNoChanges is returned when a new document
	// version has no changes compared to the previous version.
	ErrNoChanges errs.Sentinel = "no changes"
	// ErrNotImplemented is returned when an operation is not supported
	// by a particular Conn implementation.
	ErrNotImplemented errs.Sentinel = "not implemented"
	// ErrReadonly is returned by the write methods of a read-only Conn,
	// such as one created with ReadonlyConn.
	ErrReadonly errs.Sentinel = "connection is read-only"
)

///////////////////////////////////////////////////////////////////////////////
// ErrDocumentNotFound

// ErrDocumentNotFound is returned when no document with the given ID exists.
// It matches os.ErrNotExist, sql.ErrNoRows, and errs.ErrNotFound via errors.Is.
type ErrDocumentNotFound struct {
	docID uu.ID
}

// NewErrDocumentNotFound returns an ErrDocumentNotFound
// for the document with the passed docID.
func NewErrDocumentNotFound(docID uu.ID) ErrDocumentNotFound {
	return ErrDocumentNotFound{docID}
}

func (e ErrDocumentNotFound) Error() string {
	return fmt.Sprintf("document %s not found", e.docID)
}

func (ErrDocumentNotFound) Is(target error) bool {
	return target == os.ErrNotExist || target == sql.ErrNoRows || target == errs.ErrNotFound
}

func (e ErrDocumentNotFound) DocID() uu.ID {
	return e.docID
}

///////////////////////////////////////////////////////////////////////////////
// ErrDocumentFileNotFound

// ErrDocumentFileNotFound is returned when a file is not found within a document version.
// It matches errs.ErrNotFound and os.ErrNotExist via errors.Is.
type ErrDocumentFileNotFound struct {
	docID    uu.ID
	filename string
}

// NewErrDocumentFileNotFound returns an ErrDocumentFileNotFound
// for the file with the passed filename within the document with the passed docID.
func NewErrDocumentFileNotFound(docID uu.ID, filename string) ErrDocumentFileNotFound {
	return ErrDocumentFileNotFound{docID, filename}
}

func (e ErrDocumentFileNotFound) Error() string {
	return fmt.Sprintf("document %s file not found: %q", e.docID, e.filename)
}

func (ErrDocumentFileNotFound) Is(target error) bool {
	return target == errs.ErrNotFound || target == os.ErrNotExist
}
func (e ErrDocumentFileNotFound) DocID() uu.ID     { return e.docID }
func (e ErrDocumentFileNotFound) Filename() string { return e.filename }

///////////////////////////////////////////////////////////////////////////////
// ErrDocumentVersionNotFound

// ErrDocumentVersionNotFound is returned when the specified version does not exist for a document.
// It matches errs.ErrNotFound via errors.Is.
type ErrDocumentVersionNotFound struct {
	docID   uu.ID
	version VersionTime
}

// NewErrDocumentVersionNotFound returns an ErrDocumentVersionNotFound
// for the passed version of the document with the passed docID.
func NewErrDocumentVersionNotFound(docID uu.ID, version VersionTime) ErrDocumentVersionNotFound {
	return ErrDocumentVersionNotFound{docID, version}
}

func (e ErrDocumentVersionNotFound) Error() string {
	return fmt.Sprintf("document %s version %s not found", e.docID, e.version)
}

func (ErrDocumentVersionNotFound) Is(target error) bool   { return target == errs.ErrNotFound }
func (e ErrDocumentVersionNotFound) DocID() uu.ID         { return e.docID }
func (e ErrDocumentVersionNotFound) Version() VersionTime { return e.version }

///////////////////////////////////////////////////////////////////////////////
// ErrDocumentAlreadyExists

// ErrDocumentAlreadyExists is returned by CreateDocument when a document
// with the given ID already exists.
type ErrDocumentAlreadyExists struct {
	docID uu.ID
}

// NewErrDocumentAlreadyExists returns an ErrDocumentAlreadyExists
// for the document with the passed docID.
func NewErrDocumentAlreadyExists(docID uu.ID) ErrDocumentAlreadyExists {
	return ErrDocumentAlreadyExists{docID}
}

func (e ErrDocumentAlreadyExists) Error() string {
	return fmt.Sprintf("document %s already exists", e.docID)
}

///////////////////////////////////////////////////////////////////////////////
// ErrVersionAlreadyExists

// ErrVersionAlreadyExists is returned when a version with the same timestamp
// already exists for a document.
type ErrVersionAlreadyExists struct {
	docID   uu.ID
	version VersionTime
}

// NewErrVersionAlreadyExists returns an ErrVersionAlreadyExists
// for the passed version of the document with the passed docID.
func NewErrVersionAlreadyExists(docID uu.ID, version VersionTime) ErrVersionAlreadyExists {
	return ErrVersionAlreadyExists{docID, version}
}

func (e ErrVersionAlreadyExists) Error() string {
	return fmt.Sprintf("document %s version %s already exists", e.docID, e.version)
}

///////////////////////////////////////////////////////////////////////////////
// ErrPathConflict

// ErrPathConflict is returned by file-system backed Conn implementations
// when a path component required for a document directory tree is occupied
// by a non-directory entry (regular file, symlink, etc).
// It matches os.ErrExist via errors.Is.
//
// The diagnostic fields identify the offending on-disk entry so an operator
// can investigate what created it. Nothing in the current Conn write paths
// produces a non-directory at these path levels, so the presence of one
// indicates an out-of-band write (older code, manual intervention, backup
// tool, partial filesystem operation).
type ErrPathConflict struct {
	docID        uu.ID
	companyID    uu.ID
	targetPath   string
	conflictPath string
	entryType    string
	size         int64
	modTime      time.Time
}

// NewErrPathConflict returns an ErrPathConflict for the document with the
// passed docID and companyID. targetPath is the directory path that was
// expected, conflictPath is the existing non-directory entry that blocks it,
// and entryType, size, and modTime describe that offending on-disk entry.
func NewErrPathConflict(docID, companyID uu.ID, targetPath, conflictPath, entryType string, size int64, modTime time.Time) ErrPathConflict {
	return ErrPathConflict{
		docID:        docID,
		companyID:    companyID,
		targetPath:   targetPath,
		conflictPath: conflictPath,
		entryType:    entryType,
		size:         size,
		modTime:      modTime,
	}
}

func (e ErrPathConflict) Error() string {
	return fmt.Sprintf(
		"path conflict for document %s of company %s: expected directory at %s but %s is a %s (size=%d, mtime=%s)",
		e.docID, e.companyID, e.targetPath, e.conflictPath, e.entryType, e.size, e.modTime.Format(time.RFC3339Nano),
	)
}

func (ErrPathConflict) Is(target error) bool { return target == os.ErrExist }

func (e ErrPathConflict) DocID() uu.ID         { return e.docID }
func (e ErrPathConflict) CompanyID() uu.ID     { return e.companyID }
func (e ErrPathConflict) TargetPath() string   { return e.targetPath }
func (e ErrPathConflict) ConflictPath() string { return e.conflictPath }
func (e ErrPathConflict) EntryType() string    { return e.entryType }
func (e ErrPathConflict) Size() int64          { return e.size }
func (e ErrPathConflict) ModTime() time.Time   { return e.modTime }

///////////////////////////////////////////////////////////////////////////////
// ErrDocumentChanged

// ErrDocumentChanged indicates an optimistic concurrency conflict:
// the document has been modified since the version that was used as a base.
type ErrDocumentChanged struct {
	docID       uu.ID
	baseVersion VersionTime
}

// NewErrDocumentChanged returns an ErrDocumentChanged for the document with
// the passed docID, where version is the base version it was expected to
// still be at.
func NewErrDocumentChanged(docID uu.ID, version VersionTime) ErrDocumentChanged {
	return ErrDocumentChanged{docID, version}
}

func (e ErrDocumentChanged) Error() string {
	return fmt.Sprintf("document %s has changed since version %s", e.docID, e.baseVersion)
}
