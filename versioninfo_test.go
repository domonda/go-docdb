package docdb

import (
	"context"
	"reflect"
	"testing"

	fs "github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
)

const oldVersionInfoJSON = `{
	"CompanyID": "99aec0cc-c9d6-4838-8e3d-3fb562af4333",
	"DocID": "bbaea6b9-53d4-4aad-8652-79bf64432374",
	"Version": "2018-07-05_15-21-25.703",
	"PrevVersion": "2018-07-05_11-07-31.079",
	"CommitUserID": "d59e5071-3f08-4091-b5a9-bb9da199f688",
	"CommitReason": "UPLOAD_TO_ABACUS",
	"Files": {
		"0.jpg": {
			"Name": "0.jpg",
			"Size": 133831,
			"Hash": "468da7d013a2329a78c101c7b25b069249557e781d6f7db6959549307cb3f65e"
		},
		"doc.json": {
			"Name": "doc.json",
			"Size": 3703,
			"Hash": "69c8c780e5dabad7665e34f2d96857a130c6b41cd8a5663d343ec5fcdf4eb7d9"
		},
		"doc.pdf": {
			"Name": "doc.pdf",
			"Size": 285929,
			"Hash": "27f941cb56196e6f42826e9cfcfc4395e7fe414c763665e4a9288f579315d3e9"
		}
	},
	"AddedFiles": null,
	"RemovedFiles": null,
	"ModidfiedFiles": [
		"doc.json"
	]
}`

const newVersionInfoJSON = `{
	"CompanyID": "99aec0cc-c9d6-4838-8e3d-3fb562af4333",
	"DocID": "bbaea6b9-53d4-4aad-8652-79bf64432374",
	"Version": "2018-07-05_15-21-25.703",
	"PrevVersion": "2018-07-05_11-07-31.079",
	"CommitUserID": "d59e5071-3f08-4091-b5a9-bb9da199f688",
	"CommitReason": "UPLOAD_TO_ABACUS",
	"Files": {
		"0.jpg": {
			"Name": "0.jpg",
			"Size": 133831,
			"Hash": "468da7d013a2329a78c101c7b25b069249557e781d6f7db6959549307cb3f65e"
		},
		"doc.json": {
			"Name": "doc.json",
			"Size": 3703,
			"Hash": "69c8c780e5dabad7665e34f2d96857a130c6b41cd8a5663d343ec5fcdf4eb7d9"
		},
		"doc.pdf": {
			"Name": "doc.pdf",
			"Size": 285929,
			"Hash": "27f941cb56196e6f42826e9cfcfc4395e7fe414c763665e4a9288f579315d3e9"
		}
	},
	"AddedFiles": null,
	"RemovedFiles": null,
	"ModifiedFiles": [
		"doc.json"
	]
}`

func TestVersionInfoCompatibility(t *testing.T) {
	dir := fs.TempDir().Joinf("TestVersionInfoCompatibility-%s", uu.IDv4())
	dir.MakeDir()
	defer dir.RemoveRecursive()

	oldVersionInfoJSONFile := dir.Join("old.json")
	oldVersionInfoJSONFile.WriteAllString(context.Background(), oldVersionInfoJSON)

	newVersionInfoJSONFile := dir.Join("new.json")
	newVersionInfoJSONFile.WriteAllString(context.Background(), newVersionInfoJSON)

	oldVersionInfo, err := ReadVersionInfoJSON(oldVersionInfoJSONFile, false)
	if err != nil {
		t.Fatal(err)
	}

	newVersionInfo, err := ReadVersionInfoJSON(newVersionInfoJSONFile, false)
	if err != nil {
		t.Fatal(err)
	}

	if !reflect.DeepEqual(oldVersionInfo, newVersionInfo) {
		t.Fatal("not equal")
	}

	if len(oldVersionInfo.ModifiedFiles) != 1 || oldVersionInfo.ModifiedFiles[0] != "doc.json" {
		t.Fatal("ModidfiedFiles not loaded as ModifiedFiles")
	}

	copyVersionInfoJSONFile := dir.Join("copy.json")

	err = oldVersionInfo.WriteJSON(copyVersionInfoJSONFile)
	if err != nil {
		t.Fatal(err)
	}

	newVersionInfo, err = ReadVersionInfoJSON(copyVersionInfoJSONFile, false)
	if err != nil {
		t.Fatal(err)
	}

	if !reflect.DeepEqual(oldVersionInfo, newVersionInfo) {
		t.Fatal("not equal")
	}
}
