package docdb

import (
	"context"
	"maps"
	"slices"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

type HashedDocument struct {
	ID          uu.ID
	CompanyID   uu.ID
	HashedFiles map[string][]byte
	Versions    map[VersionTime]*HashedVersion
}

type HashedVersion struct {
	CommitUserID uu.ID
	CommitReason string
	FileHashes   map[string]string // filename -> hash
}

// func (v *HashedVersion) HasFile(filename string) bool {
// 	if v == nil {
// 		return false
// 	}
// 	_, ok := v.FileHashes[filename]
// 	return ok
// }

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
			data, err := versionFileProvider.ReadFile(ctx, filename)
			if err != nil {
				return nil, err
			}
			if int64(len(data)) != versionInfo.Files[filename].Size {
				return nil, errs.Errorf("document %s version %s file %q has %d bytes, but expected %d bytes according to version info", docID, version, filename, len(data), versionInfo.Files[filename].Size)
			}
			hash := ContentHash(data)
			if hash != versionInfo.Files[filename].Hash {
				return nil, errs.Errorf("document %s version %s file %q has hash %s, but expected %s according to version info", docID, version, filename, hash, versionInfo.Files[filename].Hash)
			}
			doc.HashedFiles[filename] = data
			v.FileHashes[filename] = hash
		}
		doc.Versions[version] = v
	}

	return doc, nil
}

func (doc *HashedDocument) VersionTimes() []VersionTime {
	return slices.SortedFunc(maps.Keys(doc.Versions), func(a, b VersionTime) int {
		return a.Compare(b)
	})
}

func (doc *HashedDocument) VersionInfo(versionTime VersionTime) *VersionInfo {
	var (
		prevVersionTime VersionTime
		prevVersion     *HashedVersion
		version         *HashedVersion
	)
	versions := doc.VersionTimes()
	for i, v := range versions {
		if v.Equal(versionTime) {
			if i > 0 {
				prevVersionTime = versions[i-1]
				prevVersion = doc.Versions[prevVersionTime]
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
			panic("HashedDocument is inconsistent, file hash not found in doc.HashedFiles")
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
		for _, prevFilename := range prevVersion.FileHashes {
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
