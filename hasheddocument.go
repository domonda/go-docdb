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
	ID          uu.ID
	CompanyID   uu.ID
	HashedFiles map[string][]byte              // content hash -> file data
	Versions    map[VersionTime]*HashedVersion // version timestamp -> version metadata
}

// HashedVersion holds the metadata for a single version within a HashedDocument.
type HashedVersion struct {
	CommitUserID uu.ID
	CommitReason string
	FileHashes   map[string]string // filename -> content hash
}

// Validate returns an error if the HashedDocument is structurally invalid.
// It checks for nil receiver, invalid IDs, empty Versions, invalid VersionTime,
// nil HashedVersion entries, and FileHashes references that have no corresponding
// entry in HashedFiles. All encountered problems are joined with errors.Join.
func (doc *HashedDocument) Validate() error {
	if doc == nil {
		return errs.New("nil HashedDocument")
	}
	var err error
	if e := doc.ID.Validate(); e != nil {
		err = errors.Join(err, fmt.Errorf("HashedDocument.ID is invalid: %w", e))
	}
	if e := doc.CompanyID.Validate(); e != nil {
		err = errors.Join(err, fmt.Errorf("HashedDocument.CompanyID is invalid: %w", e))
	}
	if len(doc.Versions) == 0 {
		err = errors.Join(err, errs.New("HashedDocument has no versions"))
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
	return err
}

// ReadHashedDocument reads a complete document with all versions and file content
// from a Conn into a HashedDocument. It validates file sizes and content hashes
// against the VersionInfo metadata.
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
//   - recreate=false (additive merge): the document is created on destConn
//     if missing, otherwise existing versions are kept and only versions
//     not already present on destConn are added. If the document exists,
//     its CompanyID on destConn must equal the one on srcConn, otherwise
//     the call fails without changing anything.
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

// SyncAllCompanyDocuments copies all documents of a company
// from srcConn to destConn by calling SyncDocument for every document
// enumerated via srcConn.EnumCompanyDocumentIDs.
//
// The recreate flag is passed through to SyncDocument for every document.
//
// Documents are synced one after another in enumeration order.
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
func SyncAllCompanyDocuments(ctx context.Context, srcConn, destConn Conn, companyID uu.ID, recreate, continueOnError bool) (syncedDocIDs uu.IDSlice, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, srcConn, destConn, companyID, recreate, continueOnError)

	var stop = errors.New("stop")
	enumErr := srcConn.EnumCompanyDocumentIDs(ctx, companyID, func(ctx context.Context, docID uu.ID) error {
		syncErr := SyncDocument(ctx, srcConn, destConn, docID, recreate)
		if syncErr != nil {
			err = errors.Join(err, syncErr)
			if continueOnError {
				return nil
			}
			return stop // Don't return syncErr, it's already collected in err
		}
		syncedDocIDs = append(syncedDocIDs, docID)
		return nil
	})
	if errors.Is(enumErr, stop) {
		enumErr = nil
	}
	return syncedDocIDs, errors.Join(enumErr, err)
}

// VersionTimes returns the version timestamps of the document sorted in ascending order.
func (doc *HashedDocument) VersionTimes() []VersionTime {
	return slices.SortedFunc(maps.Keys(doc.Versions), func(a, b VersionTime) int {
		return a.Compare(b)
	})
}

// VersionInfo reconstructs a VersionInfo for the given version timestamp
// by comparing against the previous version to compute added, modified,
// and removed files. Returns nil if the version does not exist or if the
// document is internally inconsistent (a referenced file hash is missing
// from HashedFiles); use Validate to detect such inconsistencies explicitly.
func (doc *HashedDocument) VersionInfo(versionTime VersionTime) *VersionInfo {
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
		return nil
	}

	info := &VersionInfo{
		CompanyID:    doc.CompanyID,
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
			// Inconsistent document (a file references a hash with no content).
			// Return nil rather than panicking; callers should Validate first.
			return nil
		}
		info.Files[filename] = FileInfo{
			Name: filename,
			Size: int64(len(data)),
			Hash: hash,
		}
		if prevVersion == nil {
			info.AddedFiles = append(info.AddedFiles, filename)
		} else {
			prevHash, ok := prevVersion.FileHashes[filename]
			if !ok {
				info.AddedFiles = append(info.AddedFiles, filename)
			} else if prevHash != hash {
				info.ModifiedFiles = append(info.ModifiedFiles, filename)
			}
		}
	}
	if prevVersion != nil {
		for prevFilename := range prevVersion.FileHashes {
			if _, ok := version.FileHashes[prevFilename]; !ok {
				info.RemovedFiles = append(info.RemovedFiles, prevFilename)
			}
		}
	}
	slices.Sort(info.AddedFiles)
	slices.Sort(info.ModifiedFiles)
	slices.Sort(info.RemovedFiles)
	return info
}
