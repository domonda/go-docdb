package localfsdb

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/domonda/go-docdb"
)

// TestVersionTimeSetMatchesEqual pins that the set answers membership the way
// docdb.VersionTime.Equal does rather than the way a map key would.
//
// The two sources a restore compares do not agree on precision: a version read
// back from a store goes through VersionTimeFrom, which truncates to
// milliseconds, while a version deserialized from a backup goes through
// VersionTimeFromString, which does not. Keyed by the VersionTime itself the
// set missed such a pair even though Equal reports them equal, and the restore
// then took the create path for a version that already existed instead of
// skipping it.
func TestVersionTimeSetMatchesEqual(t *testing.T) {
	// Sub-millisecond, the way a version string reaches this code through the
	// SQL time format VersionTimeFromString falls back to.
	fromBackup := docdb.MustVersionTimeFromString("2024-01-01 00:00:00.0005")
	fromStore := docdb.VersionTimeFrom(fromBackup.Time)

	require.True(t, fromBackup.Equal(fromStore),
		"precondition: both name the same version")
	require.NotEqual(t, fromBackup, fromStore,
		"precondition: they are distinct map keys, which is what makes this test necessary")

	set := versionTimeSet([]docdb.VersionTime{fromStore})
	require.True(t, set[versionTimeKey(fromBackup)],
		"a version the set holds must be found under an untruncated spelling of the same version")
	require.Len(t, set, 1)
}

// TestVersionTimeKeyMatchesEqual pins the contract the key has to satisfy:
// two versions get the same key exactly when VersionTime.Equal calls them
// equal. Equal truncates both sides to milliseconds, so every pair below that
// differs only below a millisecond, or only in location, must collapse onto one
// key, and every pair that differs by a whole millisecond must not.
func TestVersionTimeKeyMatchesEqual(t *testing.T) {
	ms := func(s string) docdb.VersionTime { return docdb.MustVersionTimeFromString(s) }

	for _, tc := range []struct {
		name string
		a, b docdb.VersionTime
	}{
		{
			"sub-millisecond digits are dropped, not rounded up",
			ms("2024-01-01_00-00-00.000"),
			ms("2024-01-01 00:00:00.0009"),
		},
		{
			"a version read from a store and the same one read from a backup",
			docdb.VersionTimeFrom(ms("2024-01-01 00:00:00.0005").Time),
			ms("2024-01-01 00:00:00.0005"),
		},
		{
			"the same instant in another location",
			ms("2024-01-01_05-00-00.000"),
			docdb.VersionTime{Time: time.Date(2024, 1, 1, 10, 0, 0, 0, time.FixedZone("X", 5*3600))},
		},
		{
			"before the Unix epoch, where the millisecond count is negative",
			ms("1960-01-01_00-00-00.000"),
			ms("1960-01-01 00:00:00.0009"),
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			require.True(t, tc.a.Equal(tc.b), "precondition: the two name the same version")
			require.Equal(t, versionTimeKey(tc.a), versionTimeKey(tc.b),
				"versions Equal calls equal must share a key")
		})
	}

	t.Run("a whole millisecond apart stays distinct", func(t *testing.T) {
		a := ms("2024-01-01_00-00-00.000")
		b := ms("2024-01-01_00-00-00.001")
		require.False(t, a.Equal(b), "precondition: these are different versions")
		require.NotEqual(t, versionTimeKey(a), versionTimeKey(b))
	})

	t.Run("the zero version is a stable key", func(t *testing.T) {
		require.Equal(t, versionTimeKey(docdb.VersionTime{}), versionTimeKey(docdb.VersionTime{}))
	})
}
