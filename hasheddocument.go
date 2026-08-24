package docdb

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"slices"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

// HashedDocument is an in-memory representation of a complete document
// with all versions and file content, keyed by content hash.
// It is used for backup and restore operations via ReadHashedDocument
// and Conn.RestoreDocument.
type HashedDocument struct {
	ID uu.ID
	// CompanyID is the company that currently owns the document, which is the
	// company of its latest version: a document is only listed under that
	// company. Earlier versions can name a different company, see
	// HashedVersion.CompanyID.
	CompanyID   uu.ID
	HashedFiles map[string][]byte              // content hash -> file data
	Versions    map[VersionTime]*HashedVersion // version timestamp -> version metadata
}

// HashedVersion holds the metadata for a single version within a HashedDocument.
type HashedVersion struct {
	// CompanyID is the company that owned the document when this version was
	// committed. A document is moved between companies by committing a new
	// version that names the new company, so the versions before the move keep
	// naming the previous one and the move stays visible in the document's
	// history.
	//
	// uu.IDNil means the version inherits HashedDocument.CompanyID, so a
	// HashedDocument of a document that was never moved can leave it unset.
	// The latest version must name the document's current company (see
	// Validate).
	CompanyID    uu.ID
	CommitUserID uu.ID
	CommitReason string
	FileHashes   map[string]string // filename -> content hash
}

// Validate returns an error if the HashedDocument is structurally invalid.
// It checks for nil receiver, invalid IDs, empty Versions, invalid VersionTime,
// nil HashedVersion entries, and FileHashes references that have no corresponding
// entry in HashedFiles. All encountered problems are joined with errors.Join.
//
// It also enforces the document version invariants: every version must contain
// at least one file (a document cannot be created empty, and no version may
// remove all files), and every version after the first must differ from its
// predecessor either in its files or in its company (no change-less versions),
// and the latest version must name the document's current CompanyID.
func (doc *HashedDocument) Validate() error {
	if doc == nil {
		return errors.New("nil HashedDocument")
	}
	var err error
	if e := doc.ID.Validate(); e != nil {
		err = errors.Join(err, fmt.Errorf("HashedDocument.ID is invalid: %w", e))
	}
	if e := doc.CompanyID.Validate(); e != nil {
		err = errors.Join(err, fmt.Errorf("HashedDocument.CompanyID is invalid: %w", e))
	}
	if len(doc.Versions) == 0 {
		err = errors.Join(err, errors.New("HashedDocument has no versions"))
	}
	for v, hv := range doc.Versions {
		if e := v.Validate(); e != nil {
			err = errors.Join(err, fmt.Errorf("HashedDocument version %s is invalid: %w", v, e))
		}
		if hv == nil {
			err = errors.Join(err, fmt.Errorf("HashedDocument version %s has nil HashedVersion", v))
			continue
		}
		for filename, hash := range hv.FileHashes {
			if _, ok := doc.HashedFiles[hash]; !ok {
				err = errors.Join(err, fmt.Errorf(
					"HashedDocument version %s file %q references missing hash %s",
					v, filename, hash,
				))
			}
		}
	}

	// Ordered version invariants: every version must contain at least one file
	// (no version may remove all files), and every version after the first must
	// differ from its predecessor. VersionTimes returns the versions sorted
	// ascending. Nil HashedVersions were already reported above and are skipped
	// here to avoid a nil deref.
	sorted := doc.VersionTimes()
	for i, v := range sorted {
		hv := doc.Versions[v]
		if hv == nil {
			continue
		}
		if len(hv.FileHashes) == 0 {
			err = errors.Join(err, fmt.Errorf("HashedDocument version %s has no files", v))
		}
		if i > 0 {
			// A version with the same files as its predecessor is a change-less
			// version unless it moved the document to another company, which is
			// how a move is recorded: a new version that changes nothing but the
			// company.
			prev := doc.Versions[sorted[i-1]]
			if prev != nil && maps.Equal(hv.FileHashes, prev.FileHashes) &&
				doc.VersionCompanyID(v) == doc.VersionCompanyID(sorted[i-1]) {
				err = errors.Join(err, fmt.Errorf(
					"HashedDocument version %s is identical to previous version %s (no change)",
					v, sorted[i-1],
				))
			}
		}
		// The company of the latest version is the document's current company:
		// a store that keeps no separate owner marker derives the owner from
		// its latest version, so a backup naming two different companies for it
		// would restore a document owned by whichever of the two that store
		// happens to report.
		if i == len(sorted)-1 && doc.VersionCompanyID(v) != doc.CompanyID {
			err = errors.Join(err, fmt.Errorf(
				"HashedDocument latest version %s has CompanyID %s but the document has %s",
				v, doc.VersionCompanyID(v), doc.CompanyID,
			))
		}
	}
	return err
}

// VersionCompanyID returns the company that owned the document at the passed
// version: the version's own CompanyID, or the document's CompanyID if the
// version does not name one (see HashedVersion.CompanyID).
//
// Returns the document's CompanyID for a version the document does not have.
func (doc *HashedDocument) VersionCompanyID(versionTime VersionTime) uu.ID {
	if hv := doc.Versions[versionTime]; hv != nil && !hv.CompanyID.IsNil() {
		return hv.CompanyID
	}
	return doc.CompanyID
}

// CheckRestoreCompanyID returns an error if doc must not be restored into an
// already existing document that is owned by destCompanyID and has destVersions
// as its versions in ascending order.
//
// The company of the existing document is compared against the company doc
// names for the same version, which is its latest one, and only against
// doc.CompanyID if doc does not have that version. Comparing the current
// companies of both sides instead would refuse a backup whose newer versions
// move the document to another company — the restore of a move — while
// accepting one that renames the company of versions the destination already
// has.
//
// It is used by Conn.RestoreDocument implementations for recreate=false, where
// the restore merges into the existing document instead of replacing it.
func CheckRestoreCompanyID(doc *HashedDocument, destVersions []VersionTime, destCompanyID uu.ID) error {
	expected := doc.CompanyID
	if len(destVersions) > 0 {
		destLatest := destVersions[len(destVersions)-1]
		if _, ok := doc.Versions[destLatest]; ok {
			expected = doc.VersionCompanyID(destLatest)
		}
	}
	if destCompanyID != expected {
		return errs.Errorf(
			"cannot restore document %s into existing document with different companyID: backup %s != on-disk %s",
			doc.ID, expected, destCompanyID,
		)
	}
	return nil
}

// ReadHashedDocument reads a complete document with all versions and file content
// from a Conn into a HashedDocument. It validates file sizes and content hashes
// against the VersionInfo metadata.
//
// Every version keeps the company it was committed with, so a document that was
// moved between companies is backed up with its move history intact. The
// exception is the latest version, which is read as owned by the company the
// Conn reports for the document: an implementation that keeps a separate owner
// marker can have that marker point at a company the latest version does not
// name (Conn.SetDocumentCompanyID moves the marker without committing a
// version), and the document's current owner is what an implementation without
// such a marker has to derive from its latest version.
func ReadHashedDocument(ctx context.Context, conn Conn, docID uu.ID) (doc *HashedDocument, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, conn, docID)

	doc = &HashedDocument{
		ID:          docID,
		HashedFiles: make(map[string][]byte),
		Versions:    make(map[VersionTime]*HashedVersion),
	}
	doc.CompanyID, err = conn.DocumentCompanyID(ctx, docID)
	if err != nil {
		return nil, err
	}

	versions, err := conn.DocumentVersions(ctx, docID)
	if err != nil {
		return nil, err
	}
	for _, version := range versions {
		versionInfo, err := conn.DocumentVersionInfo(ctx, docID, version)
		if err != nil {
			return nil, err
		}
		v := &HashedVersion{
			CompanyID:    versionInfo.CompanyID,
			CommitUserID: versionInfo.CommitUserID,
			CommitReason: versionInfo.CommitReason,
			FileHashes:   make(map[string]string),
		}

		versionFileProvider, err := conn.DocumentVersionFileProvider(ctx, docID, version)
		if err != nil {
			return nil, err
		}
		filenames, err := versionFileProvider.ListFiles(ctx)
		if err != nil {
			return nil, err
		}
		for _, filename := range filenames {
			fileInfo, ok := versionInfo.Files[filename]
			if !ok {
				return nil, errs.Errorf("document %s version %s file %q exists in storage but is not tracked in version info", docID, version, filename)
			}
			data, err := versionFileProvider.ReadFile(ctx, filename)
			if err != nil {
				return nil, err
			}
			if int64(len(data)) != fileInfo.Size {
				return nil, errs.Errorf("document %s version %s file %q has %d bytes, but expected %d bytes according to version info", docID, version, filename, len(data), fileInfo.Size)
			}
			hash := ContentHash(data)
			if hash != fileInfo.Hash {
				return nil, errs.Errorf("document %s version %s file %q has hash %s, but expected %s according to version info", docID, version, filename, hash, fileInfo.Hash)
			}
			doc.HashedFiles[hash] = data
			v.FileHashes[filename] = hash
		}
		for filename := range versionInfo.Files {
			if _, ok := v.FileHashes[filename]; !ok {
				return nil, errs.Errorf("document %s version %s file %q is tracked in version info but missing from storage", docID, version, filename)
			}
		}
		doc.Versions[version] = v
	}

	// DocumentVersions returns the versions ascending, so the last one is the
	// latest: the version that names the document's current company. See the
	// doc comment above for why the Conn's answer wins over what the version
	// itself recorded.
	if len(versions) > 0 {
		doc.Versions[versions[len(versions)-1]].CompanyID = doc.CompanyID
	}

	return doc, nil
}

// SyncDocument copies a document with all its versions and file content
// from srcConn to destConn.
//
// The document is read from srcConn into an in-memory HashedDocument via
// ReadHashedDocument, which verifies every file's size and content hash
// against the version metadata, and is then written to destConn via
// Conn.RestoreDocument.
//
// The recreate flag is passed through to Conn.RestoreDocument and controls
// how an already existing document on destConn is handled:
//
//   - recreate=true (replace): an existing document with the same ID on
//     destConn is deleted first, then recreated entirely from srcConn.
//     The CompanyID on destConn after the call equals the one on srcConn.
//     This is not atomic: if the restore on destConn fails partway, the old
//     document on destConn is already gone and is not restored. The source on
//     srcConn is untouched, so the document is missing on destConn only until
//     the sync is retried.
//   - recreate=false (additive merge): the document is created on destConn
//     if missing, otherwise versions already present there with all of their
//     file content are kept as-is and everything else is written — including
//     the missing files of a version whose metadata destConn already has, so
//     an interrupted sync is resumed rather than mistaken for a finished one.
//     If the document exists, its CompanyID on destConn must equal the one
//     srcConn names for the latest version destConn has, otherwise the call
//     fails without changing anything (see CheckRestoreCompanyID).
//
// Every version is written with the company it was committed with, so a
// document moved between companies keeps its move history, and the CompanyID on
// destConn after the call is the one of the latest version it holds.
//
// Returns wrapped ErrDocumentNotFound if the document does not exist on
// srcConn, and wrapped ErrNotImplemented if destConn does not support
// restoration.
func SyncDocument(ctx context.Context, srcConn, destConn Conn, docID uu.ID, recreate bool) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, srcConn, destConn, docID, recreate)

	doc, err := ReadHashedDocument(ctx, srcConn, docID)
	if err != nil {
		return err
	}
	return destConn.RestoreDocument(ctx, doc, recreate)
}

// DocProgressCallback is called by bulk operations like SyncAllCompanyDocuments
// and CopyAllCompanyDocumentFiles before processing each document so callers
// can log the progress of a running operation.
//
// docID is the document about to be processed, index is its zero-based position
// in the list of documents, and total is the number of documents to process.
type DocProgressCallback func(ctx context.Context, docID uu.ID, index, total int)

// SyncAllCompanyDocuments copies all documents of a company
// from srcConn to destConn by calling SyncDocument for every document
// returned by srcConn.CompanyDocumentIDs.
//
// All document IDs are collected first via srcConn.CompanyDocumentIDs, then
// synced one after another in that order. This makes the total number of
// documents known up-front so it can be reported via onProgress.
//
// The recreate flag is passed through to SyncDocument for every document.
//
// If onProgress is not nil it is called before syncing each document with the
// document's zero-based index and the total number of documents to sync.
//
// If continueOnError is false the sync stops at the first failing
// document and returns that error.
//
// If continueOnError is true a failing document does not stop the sync:
// the error is collected and syncing continues with the next document,
// and err is the join of all encountered errors, or nil if none.
//
// syncedDocIDs always contains the IDs of the documents
// that were synced successfully.
func SyncAllCompanyDocuments(ctx context.Context, srcConn, destConn Conn, companyID uu.ID, recreate, continueOnError bool, onProgress DocProgressCallback) (syncedDocIDs uu.IDSlice, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, srcConn, destConn, companyID, recreate, continueOnError, onProgress)

	docIDs, err := srcConn.CompanyDocumentIDs(ctx, companyID)
	if err != nil {
		return nil, err
	}

	total := len(docIDs)
	for index, docID := range docIDs {
		if onProgress != nil {
			onProgress(ctx, docID, index, total)
		}
		syncErr := SyncDocument(ctx, srcConn, destConn, docID, recreate)
		if syncErr != nil {
			err = errors.Join(err, syncErr)
			if !continueOnError {
				return syncedDocIDs, err
			}
			continue
		}
		syncedDocIDs = append(syncedDocIDs, docID)
	}
	return syncedDocIDs, err
}

// VersionTimes returns the version timestamps of the document sorted in ascending order.
func (doc *HashedDocument) VersionTimes() []VersionTime {
	return slices.SortedFunc(maps.Keys(doc.Versions), func(a, b VersionTime) int {
		return a.Compare(b)
	})
}

// VersionInfo reconstructs a VersionInfo for the given version timestamp
// by comparing against the previous version to compute added, modified,
// and removed files.
//
// VersionInfo.CompanyID is the company of that version (see VersionCompanyID),
// not the document's current company, so restoring a document that was moved
// between companies reproduces the move instead of filing every version under
// the current owner.
//
// It returns ErrDocumentVersionNotFound if the version does not exist in the
// document, and a different error if the document is internally inconsistent
// (a version references a file hash that is missing from HashedFiles), so
// corruption is never reported as a missing version. Callers that want to
// detect such inconsistencies up-front should use Validate.
func (doc *HashedDocument) VersionInfo(versionTime VersionTime) (*VersionInfo, error) {
	var (
		prevVersionTime *VersionTime
		prevVersion     *HashedVersion
		version         *HashedVersion
	)
	versions := doc.VersionTimes()
	for i, v := range versions {
		if v.Equal(versionTime) {
			if i > 0 {
				prevVersionTime = &versions[i-1]
				prevVersion = doc.Versions[*prevVersionTime]
			}
			version = doc.Versions[versionTime]
			break
		}
	}
	if version == nil {
		return nil, NewErrDocumentVersionNotFound(doc.ID, versionTime)
	}

	info := &VersionInfo{
		CompanyID:    doc.VersionCompanyID(versionTime),
		DocID:        doc.ID,
		Version:      versionTime,
		PrevVersion:  prevVersionTime,
		CommitUserID: version.CommitUserID,
		CommitReason: version.CommitReason,
		Files:        make(map[string]FileInfo),
	}
	for filename, hash := range version.FileHashes {
		data, ok := doc.HashedFiles[hash]
		if !ok {
			// Inconsistent document: a file references a hash with no content.
			// Surface it as an error rather than panicking or returning a nil
			// that callers cannot tell apart from a missing version.
			return nil, errs.Errorf(
				"HashedDocument %s version %s file %q references hash %s missing from HashedFiles",
				doc.ID, versionTime, filename, hash,
			)
		}
		info.Files[filename] = FileInfo{
			Name: filename,
			Size: int64(len(data)),
			Hash: hash,
		}
	}
	// SetFileDeltas compares only filenames and hashes, so the previous
	// version's FileInfos are built without looking its file sizes up in
	// HashedFiles: a predecessor referencing a hash without content is not
	// this version's problem to report.
	var prevFiles map[string]FileInfo
	if prevVersion != nil {
		prevFiles = make(map[string]FileInfo, len(prevVersion.FileHashes))
		for filename, hash := range prevVersion.FileHashes {
			prevFiles[filename] = FileInfo{Name: filename, Hash: hash}
		}
	}
	info.SetFileDeltas(prevFiles)
	return info, nil
}
