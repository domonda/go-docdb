package docdb

import (
	"context"
	"fmt"
	"sort"

	fs "github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

type FileInfo struct {
	Name string
	Size int64
	Hash string
}

type VersionInfo struct {
	CompanyID    uu.ID
	DocID        uu.ID
	Version      VersionTime
	PrevVersion  VersionTime
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

// NewVersionInfo uses the files from versionDir.
// If prevVersionDir is "", then all files are added to the AddedFiles slice,
// else the according diff slices RemovedFiles and ModidfiedFiles will also be filled.
// Files inversionDir and prevVersionDir with names from ignoreFiles will be ignored.
// The file slices are sorted.
func NewVersionInfo(companyID, docID uu.ID, version, prevVersion VersionTime, commitUserID uu.ID, commitReason string, versionDir, prevVersionDir fs.File, ignoreFiles ...string) (versionInfo *VersionInfo, err error) {
	versionInfo = &VersionInfo{
		CompanyID:    companyID,
		DocID:        docID,
		Version:      version,
		PrevVersion:  prevVersion,
		CommitUserID: commitUserID,
		CommitReason: commitReason,
		Files:        make(map[string]FileInfo),
	}

	err = versionDir.ListDirInfo(func(info *fs.FileInfo) error {
		for _, ignoreFile := range ignoreFiles {
			if info.Name == ignoreFile {
				return nil
			}
		}
		hash, err := info.File.ContentHash()
		if err != nil {
			return err
		}
		versionInfo.Files[info.Name] = FileInfo{
			Name: info.Name,
			Size: info.Size,
			Hash: hash,
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	if prevVersionDir == "" {
		for filename := range versionInfo.Files {
			versionInfo.AddedFiles = append(versionInfo.AddedFiles, filename)
		}
	} else {
		prevVersionFiles := make(map[string]FileInfo)
		err = prevVersionDir.ListDirInfo(func(info *fs.FileInfo) error {
			for _, ignoreFile := range ignoreFiles {
				if info.Name == ignoreFile {
					return nil
				}
			}
			hash, err := info.File.ContentHash()
			if err != nil {
				return err
			}
			prevVersionFiles[info.Name] = FileInfo{
				Name: info.Name,
				Size: info.Size,
				Hash: hash,
			}
			return nil
		})
		if err != nil {
			return nil, err
		}

		for filename, versionFileInfo := range versionInfo.Files {
			prevVersionFile, prevVersionHasFile := prevVersionFiles[filename]
			if prevVersionHasFile {
				if versionFileInfo.Hash != prevVersionFile.Hash {
					versionInfo.ModifiedFiles = append(versionInfo.ModifiedFiles, filename)
				}
			} else {
				versionInfo.AddedFiles = append(versionInfo.AddedFiles, filename)
			}
		}
		for filename := range prevVersionFiles {
			_, versionHasFile := versionInfo.Files[filename]
			if !versionHasFile {
				versionInfo.RemovedFiles = append(versionInfo.RemovedFiles, filename)
			}
		}
	}

	if len(versionInfo.AddedFiles) > 0 {
		sort.Strings(versionInfo.AddedFiles)
	}
	if len(versionInfo.RemovedFiles) > 0 {
		sort.Strings(versionInfo.RemovedFiles)
	}
	if len(versionInfo.ModifiedFiles) > 0 {
		sort.Strings(versionInfo.ModifiedFiles)
	}

	return versionInfo, nil
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

// // NewVersionInfo uses the files from versionDir.
// // If prevVersionDir is "", then all files are added to the AddedFiles slice,
// // else the according diff slices RemovedFiles and ModidfiedFiles will also be filled.
// // Files inversionDir and prevVersionDir with names from ignoreFiles will be ignored.
// // The file slices are sorted.
// func NewVersionInfo(companyID, docID uu.ID, version, prevVersion Version, commitUserID uu.ID, commitReason string, versionDir, prevVersionDir fs.File, ignoreFiles ...string) (versionInfo *VersionInfo, err error) {
// 	version.TruncateTime()
// 	prevVersion.TruncateTime()

// 	versionInfo = &VersionInfo{
// 		CompanyID:    companyID,
// 		DocID:        docID,
// 		Version:      version,
// 		PrevVersion:  prevVersion,
// 		CommitUserID: commitUserID,
// 		CommitReason: commitReason,
// 		Files:        make(map[string]FileInfo),
// 	}

// 	err = versionDir.ListDir(func(file fs.File) error {
// 		info, err := file.StatWithContentHash()
// 		if err != nil {
// 			return err
// 		}
// 		for _, ignoreFile := range ignoreFiles {
// 			if info.Name == ignoreFile {
// 				return nil
// 			}
// 		}
// 		versionInfo.Files[info.Name] = FileInfo{
// 			Name: info.Name,
// 			Size: info.Size,
// 			Hash: info.ContentHash,
// 		}
// 		return nil
// 	})
// 	if err != nil {
// 		return nil, err
// 	}

// 	if prevVersionDir == "" {
// 		for filename := range versionInfo.Files {
// 			versionInfo.AddedFiles = append(versionInfo.AddedFiles, filename)
// 		}
// 	} else {
// 		prevVersionFiles := make(map[string]FileInfo)
// 		err = prevVersionDir.ListDir(func(file fs.File) error {
// 			info, err := file.StatWithContentHash()
// 			if err != nil {
// 				return err
// 			}
// 			for _, ignoreFile := range ignoreFiles {
// 				if info.Name == ignoreFile {
// 					return nil
// 				}
// 			}
// 			prevVersionFiles[info.Name] = FileInfo{
// 				Name: info.Name,
// 				Size: info.Size,
// 				Hash: info.ContentHash,
// 			}
// 			return nil
// 		})
// 		if err != nil {
// 			return nil, err
// 		}

// 		for filename, versionFileInfo := range versionInfo.Files {
// 			prevVersionFile, prevVersionHasFile := prevVersionFiles[filename]
// 			if prevVersionHasFile {
// 				if versionFileInfo.Hash != prevVersionFile.Hash {
// 					versionInfo.ModifiedFiles = append(versionInfo.ModifiedFiles, filename)
// 				}
// 			} else {
// 				versionInfo.AddedFiles = append(versionInfo.AddedFiles, filename)
// 			}
// 		}
// 		for filename := range prevVersionFiles {
// 			_, versionHasFile := versionInfo.Files[filename]
// 			if !versionHasFile {
// 				versionInfo.RemovedFiles = append(versionInfo.RemovedFiles, filename)
// 			}
// 		}
// 	}

// 	if len(versionInfo.AddedFiles) > 0 {
// 		sort.Strings(versionInfo.AddedFiles)
// 	}
// 	if len(versionInfo.RemovedFiles) > 0 {
// 		sort.Strings(versionInfo.RemovedFiles)
// 	}
// 	if len(versionInfo.ModifiedFiles) > 0 {
// 		sort.Strings(versionInfo.ModifiedFiles)
// 	}

// 	return versionInfo, nil
// }
