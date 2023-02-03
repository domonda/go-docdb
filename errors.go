package docdb

import (
	"database/sql"
	"errors"
	"fmt"
	"os"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

///////////////////////////////////////////////////////////////////////////////
// ErrDocumentNotFound

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
// ErrDocumentVersionAlreadyExists

type ErrDocumentVersionAlreadyExists struct {
	docID   uu.ID
	version VersionTime
}

func NewErrDocumentVersionAlreadyExists(docID uu.ID, version VersionTime) ErrDocumentVersionAlreadyExists {
	return ErrDocumentVersionAlreadyExists{docID, version}
}

func (e ErrDocumentVersionAlreadyExists) Error() string {
	return fmt.Sprintf("document %s version %s already exists", e.docID, e.version)
}

///////////////////////////////////////////////////////////////////////////////
// ErrDocumentHasNoCommitedVersion

type ErrDocumentHasNoCommitedVersion struct {
	docID uu.ID
}

func NewErrDocumentHasNoCommitedVersion(docID uu.ID) ErrDocumentHasNoCommitedVersion {
	return ErrDocumentHasNoCommitedVersion{docID}
}

func (e ErrDocumentHasNoCommitedVersion) Error() string {
	return fmt.Sprintf("document %s has no commited version yet", e.docID)
}

///////////////////////////////////////////////////////////////////////////////
// ErrDocumentNotCheckedOut

type ErrDocumentNotCheckedOut struct {
	docID uu.ID
}

func NewErrDocumentNotCheckedOut(docID uu.ID) ErrDocumentNotCheckedOut {
	return ErrDocumentNotCheckedOut{docID}
}

func (e ErrDocumentNotCheckedOut) Error() string {
	return fmt.Sprintf("document %s not checked out", e.docID)
}

///////////////////////////////////////////////////////////////////////////////
// ErrDocumentCheckedOut

type ErrDocumentCheckedOut struct {
	status *CheckOutStatus
}

func NewErrDocumentCheckedOut(status *CheckOutStatus) ErrDocumentCheckedOut {
	if status == nil {
		panic("nil CheckOutStatus")
	}
	return ErrDocumentCheckedOut{status}
}

func (e ErrDocumentCheckedOut) Error() string {
	return fmt.Sprintf(
		"document %s version %s already checked out by %s for %s at %s",
		e.status.DocID,
		e.status.Version,
		e.status.UserID,
		e.status.Reason,
		e.status.Time,
	)
}

func (e ErrDocumentCheckedOut) CheckOutUserID() uu.ID  { return e.status.UserID }
func (e ErrDocumentCheckedOut) CheckOutReason() string { return e.status.Reason }

func IsErrDocumentCheckedOutByUser(err error, userID uu.ID) bool {
	var e ErrDocumentCheckedOut
	if errors.As(err, &e) {
		return e.status.UserID == userID
	}
	return false
}
