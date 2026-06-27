package docdb

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"

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
	PrevVersion *VersionTime `json:",omitempty"`
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

// UnmarshalJSON implements the json.Unmarshaler interface.
// It handles historic JSON files where PrevVersion may be
// an empty string instead of null for the first version.
func (vi *VersionInfo) UnmarshalJSON(data []byte) error {
	// Use type alias to get default unmarshaling without infinite recursion
	type Alias VersionInfo
	aux := &struct {
		PrevVersion *string `json:"PrevVersion,omitempty"`
		*Alias
	}{
		Alias: (*Alias)(vi),
	}
	err := json.Unmarshal(data, aux)
	if err != nil {
		return err
	}
	if aux.PrevVersion == nil || *aux.PrevVersion == "" {
		vi.PrevVersion = nil
	} else {
		vt, err := VersionTimeFromString(*aux.PrevVersion)
		if err != nil {
			return err
		}
		vi.PrevVersion = &vt
	}
	return nil
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
	for name, info := range vi.Files {
		otherInfo, ok := other.Files[name]
		if !ok || otherInfo != info {
			return false
		}
	}
	return true
}

// Equal reports whether vi and other describe the same committed version:
// identical scalar metadata (company, document, version, previous version,
// commit user and reason), the same added/removed/modified filename sets
// (compared order-insensitively, since callers derive them from map
// iteration), and the same resolved file set (see EqualFiles).
//
// Keeping the full comparison here means a field added to VersionInfo is
// compared by every caller, instead of being silently missed by a hand-rolled
// field-by-field check elsewhere.
func (vi *VersionInfo) Equal(other *VersionInfo) bool {
	if vi == other {
		return true
	}
	if vi == nil || other == nil {
		return false
	}
	if vi.CompanyID != other.CompanyID ||
		vi.DocID != other.DocID ||
		!vi.Version.Equal(other.Version) ||
		!equalVersionTimePtr(vi.PrevVersion, other.PrevVersion) ||
		vi.CommitUserID != other.CommitUserID ||
		vi.CommitReason != other.CommitReason {
		return false
	}
	if !equalStringSets(vi.AddedFiles, other.AddedFiles) ||
		!equalStringSets(vi.RemovedFiles, other.RemovedFiles) ||
		!equalStringSets(vi.ModifiedFiles, other.ModifiedFiles) {
		return false
	}
	return vi.EqualFiles(other)
}

// equalVersionTimePtr reports whether two optional VersionTimes are equal,
// treating two nil pointers as equal.
func equalVersionTimePtr(a, b *VersionTime) bool {
	if a == nil || b == nil {
		return a == b
	}
	return a.Equal(*b)
}

// equalStringSets reports whether a and b contain the same strings regardless
// of order. The input slices are not modified.
func equalStringSets(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	return slices.Equal(slices.Sorted(slices.Values(a)), slices.Sorted(slices.Values(b)))
}
