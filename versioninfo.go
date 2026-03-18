package docdb

import (
	"context"
	"fmt"

	fs "github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

type VersionInfo struct {
	CompanyID    uu.ID
	DocID        uu.ID
	Version      VersionTime
	PrevVersion  *VersionTime
	CommitUserID uu.ID
	CommitReason string

	Files         map[string]FileInfo
	AddedFiles    []string
	RemovedFiles  []string
	ModifiedFiles []string
}

func (vi *VersionInfo) String() string {
	if vi == nil {
		return "VersionInfo<nil>"
	}
	return fmt.Sprintf("VersionInfo{DocID:%s, Version:%s}", vi.DocID, vi.Version)
}

func (vi *VersionInfo) WriteJSON(file fs.File) error {
	return file.WriteJSON(context.Background(), vi, "  ")
}

func ReadVersionInfoJSON(file fs.File, writeFixedVersion bool) (versionInfo *VersionInfo, err error) {
	var i struct {
		VersionInfo
		ModidfiedFiles []string // with typo
	}
	err = file.ReadJSON(context.Background(), &i)
	if err != nil {
		return nil, err
	}
	if len(i.ModidfiedFiles) > 0 && len(i.ModifiedFiles) == 0 {
		i.ModifiedFiles = i.ModidfiedFiles
		if writeFixedVersion {
			log.Info("Fixing old VersionInfo format").Str("file", string(file)).Log()
			err = i.VersionInfo.WriteJSON(file)
			if err != nil {
				return nil, err
			}
		} else {
			log.Info("Loading old VersionInfo format").Str("file", string(file)).Log()
		}
	}
	return &i.VersionInfo, nil
}

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
