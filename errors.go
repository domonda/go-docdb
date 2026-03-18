package docdb

import (
	"database/sql"
	"fmt"
	"os"

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
)

///////////////////////////////////////////////////////////////////////////////
// ErrDocumentNotFound

// ErrDocumentNotFound is returned when no document with the given ID exists.
// It matches os.ErrNotExist, sql.ErrNoRows, and errs.ErrNotFound via errors.Is.
type ErrDocumentNotFound struct {
	docID uu.ID
}

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

func NewErrVersionAlreadyExists(docID uu.ID, version VersionTime) ErrVersionAlreadyExists {
	return ErrVersionAlreadyExists{docID, version}
}

func (e ErrVersionAlreadyExists) Error() string {
	return fmt.Sprintf("document %s version %s already exists", e.docID, e.version)
}

///////////////////////////////////////////////////////////////////////////////
// ErrDocumentChanged

// ErrDocumentChanged indicates an optimistic concurrency conflict:
// the document has been modified since the version that was used as a base.
type ErrDocumentChanged struct {
	docID       uu.ID
	baseVersion VersionTime
}

func NewErrDocumentChanged(docID uu.ID, version VersionTime) ErrDocumentChanged {
	return ErrDocumentChanged{docID, version}
}

func (e ErrDocumentChanged) Error() string {
	return fmt.Sprintf("document %s has changed since version %s", e.docID, e.baseVersion)
}
