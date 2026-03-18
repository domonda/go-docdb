package docdb

import (
	"context"
	"fmt"

	fs "github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

// VersionInfo holds metadata for a single committed document version,
// including which files changed relative to the previous version.
type VersionInfo struct {
	// CompanyID is the UUID of the company that owns the document at this version.
	CompanyID uu.ID
	// DocID is the UUID of the document.
	DocID uu.ID
	// Version is the timestamp identifying this version.
	Version VersionTime
	// PrevVersion is the timestamp of the previous version, or nil for the first version.
	PrevVersion *VersionTime
	// CommitUserID is the UUID of the user who committed this version.
	CommitUserID uu.ID
	// CommitReason describes why this version was created.
	CommitReason string

	// Files maps filename to FileInfo for every file in this version.
	Files map[string]FileInfo
	// AddedFiles lists filenames that are new in this version (not in the previous version).
	AddedFiles []string
	// RemovedFiles lists filenames that were in the previous version but removed in this one.
	RemovedFiles []string
	// ModifiedFiles lists filenames present in both versions whose content hash differs.
	ModifiedFiles []string
}

// String returns a short human-readable representation of the VersionInfo.
// Returns "VersionInfo<nil>" for a nil receiver.
func (vi *VersionInfo) String() string {
	if vi == nil {
		return "VersionInfo<nil>"
	}
	return fmt.Sprintf("VersionInfo{DocID:%s, Version:%s}", vi.DocID, vi.Version)
}

// WriteJSON writes the VersionInfo as indented JSON to the given file.
func (vi *VersionInfo) WriteJSON(file fs.File) error {
	return file.WriteJSON(context.Background(), vi, "  ")
}

// EqualFiles returns true if both VersionInfos have the same set of files
// with identical names, sizes, and content hashes.
func (vi *VersionInfo) EqualFiles(other *VersionInfo) bool {
	if vi == other {
		return true
	}
	if vi == nil || other == nil {
		return false
	}
	if len(vi.Files) != len(other.Files) {
		return false
	}
	for i := range vi.Files {
		found := false
		for j := range other.Files {
			if other.Files[j] == vi.Files[i] {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}
