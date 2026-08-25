package storeconn

import (
	"testing"

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

// TestVersionTimeKeyIsCompact pins the key format, which is only ever compared
// and never read, so it is the shortest exact spelling of the truncated instant
// rather than the human-readable VersionTime.String().
func TestVersionTimeKeyIsCompact(t *testing.T) {
	v := docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000")
	require.Equal(t, "1704067200000", versionTimeKey(v))
	require.Less(t, len(versionTimeKey(v)), len(v.String()))
}
