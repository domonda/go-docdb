package docdb

import (
	"encoding/json"
	"maps"
	"reflect"
	"slices"
	"testing"

	"github.com/domonda/go-types/uu"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestVersionInfo_UnmarshalJSON(t *testing.T) {
	companyID := uu.IDMustFromString("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
	docID := uu.IDMustFromString("11111111-2222-3333-4444-555555555555")
	commitUserID := uu.IDMustFromString("99999999-8888-7777-6666-555555555555")

	for _, scenario := range []struct {
		name            string
		json            string
		expectErr       bool
		expectVersion   string
		expectPrevNil   bool
		expectPrevValue string
	}{
		{
			name: "Full version info with PrevVersion",
			json: `{
				"CompanyID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
				"DocID": "11111111-2222-3333-4444-555555555555",
				"Version": "2026-03-23_14-19-22.200",
				"PrevVersion": "2026-03-22_10-00-00.000",
				"CommitUserID": "99999999-8888-7777-6666-555555555555",
				"CommitReason": "test commit",
				"Files": {"doc.pdf": {"Name": "doc.pdf", "Size": 1234, "Hash": "abc"}},
				"AddedFiles": ["doc.pdf"]
			}`,
			expectVersion:   "2026-03-23_14-19-22.200",
			expectPrevNil:   false,
			expectPrevValue: "2026-03-22_10-00-00.000",
		},
		{
			name: "First version without PrevVersion field",
			json: `{
				"CompanyID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
				"DocID": "11111111-2222-3333-4444-555555555555",
				"Version": "2026-03-23_14-19-22.200",
				"CommitUserID": "99999999-8888-7777-6666-555555555555",
				"CommitReason": "initial import"
			}`,
			expectVersion: "2026-03-23_14-19-22.200",
			expectPrevNil: true,
		},
		{
			name: "PrevVersion is null",
			json: `{
				"CompanyID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
				"DocID": "11111111-2222-3333-4444-555555555555",
				"Version": "2026-03-23_14-19-22.200",
				"PrevVersion": null,
				"CommitUserID": "99999999-8888-7777-6666-555555555555",
				"CommitReason": "initial import"
			}`,
			expectVersion: "2026-03-23_14-19-22.200",
			expectPrevNil: true,
		},
		{
			name: "PrevVersion is empty string (historic files)",
			json: `{
				"CompanyID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
				"DocID": "11111111-2222-3333-4444-555555555555",
				"Version": "2026-03-23_14-19-22.200",
				"PrevVersion": "",
				"CommitUserID": "99999999-8888-7777-6666-555555555555",
				"CommitReason": "initial import"
			}`,
			expectVersion: "2026-03-23_14-19-22.200",
			expectPrevNil: true,
		},
		{
			name: "PrevVersion is invalid string",
			json: `{
				"CompanyID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
				"DocID": "11111111-2222-3333-4444-555555555555",
				"Version": "2026-03-23_14-19-22.200",
				"PrevVersion": "not-a-valid-time",
				"CommitUserID": "99999999-8888-7777-6666-555555555555",
				"CommitReason": "initial import"
			}`,
			expectErr: true,
		},
		{
			name: "Version in SQL time format",
			json: `{
				"CompanyID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
				"DocID": "11111111-2222-3333-4444-555555555555",
				"Version": "2026-03-23 14:19:22.200",
				"CommitUserID": "99999999-8888-7777-6666-555555555555",
				"CommitReason": "sql format version"
			}`,
			expectVersion: "2026-03-23_14-19-22.200",
			expectPrevNil: true,
		},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			// when
			var vi VersionInfo
			err := json.Unmarshal([]byte(scenario.json), &vi)

			// then
			if scenario.expectErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)

			assert.Equal(t, companyID, vi.CompanyID)
			assert.Equal(t, docID, vi.DocID)
			assert.Equal(t, commitUserID, vi.CommitUserID)
			assert.Equal(t, scenario.expectVersion, vi.Version.String())

			if scenario.expectPrevNil {
				assert.Nil(t, vi.PrevVersion)
			} else {
				require.NotNil(t, vi.PrevVersion)
				assert.Equal(t, scenario.expectPrevValue, vi.PrevVersion.String())
			}
		})
	}
}

// baseVersionInfo returns a fully-populated VersionInfo used as the fixture
// for the Equal tests. Each test clones it and mutates the clone.
func baseVersionInfo() *VersionInfo {
	prev := MustVersionTimeFromString("2026-03-22_10-00-00.000")
	return &VersionInfo{
		CompanyID:    uu.IDMustFromString("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
		DocID:        uu.IDMustFromString("11111111-2222-3333-4444-555555555555"),
		Version:      MustVersionTimeFromString("2026-03-23_14-19-22.200"),
		PrevVersion:  &prev,
		CommitUserID: uu.IDMustFromString("99999999-8888-7777-6666-555555555555"),
		CommitReason: "test commit",
		Files: map[string]FileInfo{
			"a.pdf": {Name: "a.pdf", Size: 100, Hash: "hashA"},
			"b.pdf": {Name: "b.pdf", Size: 200, Hash: "hashB"},
		},
		AddedFiles:    []string{"a.pdf", "b.pdf"},
		RemovedFiles:  []string{"old1.pdf", "old2.pdf"},
		ModifiedFiles: []string{"m1.pdf", "m2.pdf"},
	}
}

// cloneVersionInfo returns a deep copy so a test can mutate slices/map
// without affecting the shared base fixture.
func cloneVersionInfo(vi *VersionInfo) *VersionInfo {
	c := *vi
	if vi.PrevVersion != nil {
		p := *vi.PrevVersion
		c.PrevVersion = &p
	}
	c.Files = maps.Clone(vi.Files)
	c.AddedFiles = slices.Clone(vi.AddedFiles)
	c.RemovedFiles = slices.Clone(vi.RemovedFiles)
	c.ModifiedFiles = slices.Clone(vi.ModifiedFiles)
	return &c
}

func TestVersionInfo_Equal(t *testing.T) {
	for _, tc := range []struct {
		name        string
		modify      func(vi *VersionInfo)
		expectEqual bool
	}{
		{
			name:        "identical",
			modify:      func(*VersionInfo) {},
			expectEqual: true,
		},
		// The reordered cases are the regression these tests exist for:
		// AddedFiles/RemovedFiles/ModifiedFiles are derived from map
		// iteration, so their order is non-deterministic and must not
		// affect equality. The former reflect.DeepEqual-based check
		// compared them positionally and wrongly reported reordered sets
		// as different; Equal compares them order-insensitively.
		{
			name:        "reordered AddedFiles",
			modify:      func(vi *VersionInfo) { vi.AddedFiles = []string{"b.pdf", "a.pdf"} },
			expectEqual: true,
		},
		{
			name:        "reordered RemovedFiles",
			modify:      func(vi *VersionInfo) { vi.RemovedFiles = []string{"old2.pdf", "old1.pdf"} },
			expectEqual: true,
		},
		{
			name:        "reordered ModifiedFiles",
			modify:      func(vi *VersionInfo) { vi.ModifiedFiles = []string{"m2.pdf", "m1.pdf"} },
			expectEqual: true,
		},
		{
			name: "all change slices reordered",
			modify: func(vi *VersionInfo) {
				vi.AddedFiles = []string{"b.pdf", "a.pdf"}
				vi.RemovedFiles = []string{"old2.pdf", "old1.pdf"}
				vi.ModifiedFiles = []string{"m2.pdf", "m1.pdf"}
			},
			expectEqual: true,
		},
		// nil-vs-empty tolerance is the exact contract that makes swapping
		// reflect.DeepEqual for Equal correct: reflect.DeepEqual treats a nil
		// slice/map as different from an empty one, Equal does not. Drivers
		// that represent "no added files" as nil vs []string{} describe the
		// same version and must compare equal.
		{
			name: "nil vs empty AddedFiles",
			modify: func(vi *VersionInfo) {
				vi.AddedFiles = nil
			},
			expectEqual: false, // base has 2 entries, so this genuinely differs
		},
		{
			name: "both empty vs both nil change slices",
			modify: func(vi *VersionInfo) {
				vi.AddedFiles = []string{}
				vi.RemovedFiles = []string{}
				vi.ModifiedFiles = []string{}
			},
			expectEqual: false, // base is non-empty, so this differs too
		},
		{
			name: "same-length change slice with a swapped element",
			modify: func(vi *VersionInfo) {
				// Same length as base ["a.pdf","b.pdf"] but different content:
				// guards against a naive contains/length-only comparison.
				vi.AddedFiles = []string{"a.pdf", "x.pdf"}
			},
			expectEqual: false,
		},
		{
			name: "same-length change slice with a duplicate",
			modify: func(vi *VersionInfo) {
				// Multiset check: ["a.pdf","a.pdf"] must not equal ["a.pdf","b.pdf"].
				vi.AddedFiles = []string{"a.pdf", "a.pdf"}
			},
			expectEqual: false,
		},
		{
			name:        "different CompanyID",
			modify:      func(vi *VersionInfo) { vi.CompanyID = uu.IDMustFromString("cccccccc-cccc-cccc-cccc-cccccccccccc") },
			expectEqual: false,
		},
		{
			name:        "different DocID",
			modify:      func(vi *VersionInfo) { vi.DocID = uu.IDMustFromString("dddddddd-dddd-dddd-dddd-dddddddddddd") },
			expectEqual: false,
		},
		{
			name:        "different Version",
			modify:      func(vi *VersionInfo) { vi.Version = MustVersionTimeFromString("2026-03-23_14-19-22.201") },
			expectEqual: false,
		},
		{
			name:        "different PrevVersion",
			modify:      func(vi *VersionInfo) { p := MustVersionTimeFromString("2026-03-21_10-00-00.000"); vi.PrevVersion = &p },
			expectEqual: false,
		},
		{
			name:        "PrevVersion set to nil",
			modify:      func(vi *VersionInfo) { vi.PrevVersion = nil },
			expectEqual: false,
		},
		{
			name:        "different CommitUserID",
			modify:      func(vi *VersionInfo) { vi.CommitUserID = uu.IDMustFromString("12345678-1234-1234-1234-123456789012") },
			expectEqual: false,
		},
		{
			name:        "different CommitReason",
			modify:      func(vi *VersionInfo) { vi.CommitReason = "other reason" },
			expectEqual: false,
		},
		{
			name:        "different file hash",
			modify:      func(vi *VersionInfo) { vi.Files["a.pdf"] = FileInfo{Name: "a.pdf", Size: 100, Hash: "changed"} },
			expectEqual: false,
		},
		{
			name:        "different file size",
			modify:      func(vi *VersionInfo) { vi.Files["a.pdf"] = FileInfo{Name: "a.pdf", Size: 999, Hash: "hashA"} },
			expectEqual: false,
		},
		{
			name:        "extra file",
			modify:      func(vi *VersionInfo) { vi.Files["c.pdf"] = FileInfo{Name: "c.pdf", Size: 300, Hash: "hashC"} },
			expectEqual: false,
		},
		{
			name:        "extra AddedFiles entry",
			modify:      func(vi *VersionInfo) { vi.AddedFiles = append(vi.AddedFiles, "c.pdf") },
			expectEqual: false,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			base := baseVersionInfo()
			other := cloneVersionInfo(base)
			tc.modify(other)

			assert.Equal(t, tc.expectEqual, base.Equal(other), "base.Equal(other)")
			// Equal must be symmetric.
			assert.Equal(t, tc.expectEqual, other.Equal(base), "other.Equal(base)")
		})
	}
}

func TestVersionInfo_Equal_NilHandling(t *testing.T) {
	vi := baseVersionInfo()

	assert.True(t, (*VersionInfo)(nil).Equal(nil), "nil equals nil")
	assert.True(t, vi.Equal(vi), "same pointer equals itself")
	assert.False(t, vi.Equal(nil), "non-nil equals nil")
	assert.False(t, (*VersionInfo)(nil).Equal(vi), "nil equals non-nil")
}

// TestVersionInfo_Equal_NilVsEmpty pins the contract that makes swapping
// reflect.DeepEqual for Equal safe: reflect.DeepEqual reports a nil slice/map
// as different from an empty one, but two versions that represent "nothing
// added/removed/modified" as nil vs empty describe the same version and must
// compare equal.
func TestVersionInfo_Equal_NilVsEmpty(t *testing.T) {
	a := baseVersionInfo()
	a.AddedFiles = nil
	a.RemovedFiles = nil
	a.ModifiedFiles = nil

	b := baseVersionInfo()
	b.AddedFiles = []string{}
	b.RemovedFiles = []string{}
	b.ModifiedFiles = []string{}

	assert.True(t, a.Equal(b), "nil change slices must equal empty change slices")
	assert.True(t, b.Equal(a), "symmetric")

	a.Files = nil
	b.Files = map[string]FileInfo{}
	assert.True(t, a.Equal(b), "nil Files map must equal empty Files map")
	assert.True(t, b.Equal(a), "symmetric")
}

// TestVersionInfo_Equal_ComparesEveryField guards the promise in
// VersionInfo.Equal's doc comment: every field must be compared, so a field
// added to the struct without being added to Equal is a silent correctness
// hole. If this fails because you added a field, update VersionInfo.Equal to
// compare it, add a case to TestVersionInfo_Equal, then bump the count here.
func TestVersionInfo_Equal_ComparesEveryField(t *testing.T) {
	const fieldsComparedByEqual = 10
	got := reflect.TypeFor[VersionInfo]().NumField()
	assert.Equal(t, fieldsComparedByEqual, got,
		"VersionInfo field count changed — update VersionInfo.Equal to compare the new field, then update this guard")
}

// TestVersionInfo_SetFileDeltas pins the shared derivation of the change
// lists. Every Conn implementation derives them here, and a document copied
// between implementations has its VersionInfo compared against the already
// stored one, so a difference in this derivation would not fail a test but a
// migration, halfway through a company's documents.
func TestVersionInfo_SetFileDeltas(t *testing.T) {
	files := func(nameHash ...string) map[string]FileInfo {
		if nameHash == nil {
			return nil
		}
		m := make(map[string]FileInfo, len(nameHash)/2)
		for i := 0; i < len(nameHash); i += 2 {
			m[nameHash[i]] = FileInfo{Name: nameHash[i], Size: 1, Hash: nameHash[i+1]}
		}
		return m
	}

	for _, tc := range []struct {
		name         string
		versionFiles map[string]FileInfo
		prevFiles    map[string]FileInfo
		wantAdded    []string
		wantModified []string
		wantRemoved  []string
	}{
		{
			// The first version of a document has no predecessor:
			// all of its files are added.
			name:         "nil prevFiles adds everything",
			versionFiles: files("b.pdf", "hashB", "a.pdf", "hashA"),
			prevFiles:    nil,
			wantAdded:    []string{"a.pdf", "b.pdf"},
		},
		{
			// A nil and an empty predecessor must not describe
			// different versions.
			name:         "empty prevFiles adds everything",
			versionFiles: files("a.pdf", "hashA"),
			prevFiles:    map[string]FileInfo{},
			wantAdded:    []string{"a.pdf"},
		},
		{
			name:         "unchanged files are not listed",
			versionFiles: files("a.pdf", "hashA", "b.pdf", "hashB"),
			prevFiles:    files("a.pdf", "hashA", "b.pdf", "hashB"),
		},
		{
			// Only the hash decides whether a file counts as modified,
			// so a version that rewrites a file with identical content
			// does not claim a change.
			name:         "same name and hash with different size is unchanged",
			versionFiles: map[string]FileInfo{"a.pdf": {Name: "a.pdf", Size: 100, Hash: "hashA"}},
			prevFiles:    map[string]FileInfo{"a.pdf": {Name: "a.pdf", Size: 999, Hash: "hashA"}},
		},
		{
			name:         "added, modified and removed together",
			versionFiles: files("keep.pdf", "hashK", "mod.pdf", "hashM2", "new.pdf", "hashN"),
			prevFiles:    files("keep.pdf", "hashK", "mod.pdf", "hashM1", "gone.pdf", "hashG"),
			wantAdded:    []string{"new.pdf"},
			wantModified: []string{"mod.pdf"},
			wantRemoved:  []string{"gone.pdf"},
		},
		{
			name:         "all files removed",
			versionFiles: nil,
			prevFiles:    files("a.pdf", "hashA", "b.pdf", "hashB"),
			wantRemoved:  []string{"a.pdf", "b.pdf"},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			vi := &VersionInfo{Files: tc.versionFiles}
			vi.SetFileDeltas(tc.prevFiles)

			// Sorted, not just set-equal: the lists are persisted as-is
			// (JSON file, Postgres array), so they must not depend on
			// map iteration order.
			assert.Equal(t, tc.wantAdded, vi.AddedFiles)
			assert.Equal(t, tc.wantModified, vi.ModifiedFiles)
			assert.Equal(t, tc.wantRemoved, vi.RemovedFiles)
		})
	}
}

// TestVersionInfo_SetFileDeltas_ReplacesLists documents that the lists are
// replaced instead of appended to, and that a list without entries stays nil:
// callers compare these lists directly and persist them.
func TestVersionInfo_SetFileDeltas_ReplacesLists(t *testing.T) {
	vi := baseVersionInfo()
	vi.Files = map[string]FileInfo{"a.pdf": {Name: "a.pdf", Size: 100, Hash: "hashA"}}

	vi.SetFileDeltas(map[string]FileInfo{"a.pdf": {Name: "a.pdf", Size: 100, Hash: "hashA"}})

	assert.Nil(t, vi.AddedFiles)
	assert.Nil(t, vi.ModifiedFiles)
	assert.Nil(t, vi.RemovedFiles)
}
