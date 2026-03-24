package docdb

import (
	"encoding/json"
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
