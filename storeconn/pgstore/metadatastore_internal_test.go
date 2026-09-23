package pgstore

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/internal/logcapture"
)

// TestVersionRecordCorrectionLog covers the audit record of a corrected version
// at the point it is written.
//
// The line is the only surviving account of the values the correction
// overwrote, see versionRecordCorrection: the source store those values came
// from is the one the migration exists to retire, so a field logged under the
// wrong key or dropped is not a cosmetic defect but the loss of the record
// itself, and nothing downstream would notice.
func TestVersionRecordCorrectionLog(t *testing.T) {
	t.Run("Writes nothing for a version that needed no correction", func(t *testing.T) {
		// given: the nil correction CreateDocumentVersion holds for every
		// version it did not have to correct, which is almost all of them. It
		// logs unconditionally after the transaction returned, whether that
		// transaction failed or not, so the nil receiver is the normal case
		// rather than a defensive check — and a failed call that corrected
		// nothing must stay silent about corrections.
		decode := logcapture.Start(t)
		var correction *versionRecordCorrection

		// when
		correction.log(t.Context(), nil)
		correction.log(t.Context(), errs.New("commit failed"))

		// then
		require.Empty(t, decode())
	})

	t.Run("Writes what the correction overwrote and what replaced it", func(t *testing.T) {
		// given: the three delta lists carry different values, so a list
		// logged under another list's key is visible here. They are written
		// whenever a correction happens at all, so a version whose own file
		// records were already right has an empty correctedFiles and the delta
		// write as the only thing that happened to it.
		decode := logcapture.Start(t)
		docID := uu.IDv7()
		version := docdb.MustVersionTimeFromString("2024-01-01_00-00-01.000")
		correction := &versionRecordCorrection{
			docID:          docID,
			version:        version,
			correctedFiles: []string{"doc.json"},
			corrections:    []string{"doc.json: 10 bytes hash-before -> 20 bytes hash-after"},
			addedFiles:     []string{"added.pdf"},
			modifiedFiles:  []string{"modified.pdf"},
			removedFiles:   []string{"removed.pdf"},
		}

		// when
		correction.log(t.Context(), nil)

		// then
		messages := decode()
		require.Len(t, messages, 1)
		message := messages[0]
		// ERROR, not WARN: a stored record contradicting the content it
		// describes is the failure the migration exists to find, and the line
		// has to survive a production log level that drops anything below.
		require.Equal(t, "ERROR", message["level"])
		require.Contains(t, message["message"], "Corrected the stored record of a document version")
		require.Equal(t, docID.String(), message["docID"])
		require.Equal(t, version.String(), message["version"])
		require.Equal(t, []any{"doc.json"}, message["correctedFiles"])
		require.Equal(t, []any{"doc.json: 10 bytes hash-before -> 20 bytes hash-after"}, message["corrections"])
		require.Equal(t, []any{"added.pdf"}, message["addedFiles"])
		require.Equal(t, []any{"modified.pdf"}, message["modifiedFiles"])
		require.Equal(t, []any{"removed.pdf"}, message["removedFiles"])
	})

	t.Run("Writes the deltas for a version whose own file records were already right", func(t *testing.T) {
		// given: the case reconcileStoredVersionFileRecords singles out, where
		// the delta write is the only thing that happened to the version, so
		// correctedFiles and corrections are empty. The line still has to be
		// written and still has to carry the deltas: they are what was
		// overwritten, and nothing else records the values they replaced.
		decode := logcapture.Start(t)
		correction := &versionRecordCorrection{
			docID:          uu.IDv7(),
			version:        docdb.MustVersionTimeFromString("2024-01-01_00-00-01.000"),
			correctedFiles: []string{},
			corrections:    []string{},
			addedFiles:     []string{"added.pdf"},
			modifiedFiles:  []string{"modified.pdf"},
			removedFiles:   []string{"removed.pdf"},
		}

		// when
		correction.log(t.Context(), nil)

		// then
		messages := decode()
		require.Len(t, messages, 1)
		message := messages[0]
		require.Equal(t, []any{}, message["correctedFiles"])
		require.Equal(t, []any{}, message["corrections"])
		require.Equal(t, []any{"added.pdf"}, message["addedFiles"])
		require.Equal(t, []any{"modified.pdf"}, message["modifiedFiles"])
		require.Equal(t, []any{"removed.pdf"}, message["removedFiles"])
	})

	t.Run("Keeps the record of a correction whose transaction failed", func(t *testing.T) {
		// given: a correction that was written and whose transaction then
		// returned an error. The error does not mean the writes are gone — a
		// COMMIT the server applied but could not acknowledge, a released
		// savepoint in a transaction the caller still commits, and a caller
		// with no transaction that autocommitted each write all leave them
		// stored (see versionRecordCorrection). Dropping the line here would
		// lose the only account of the overwritten values in precisely those
		// cases, so it is written and says the fate is unknown instead.
		decode := logcapture.Start(t)
		correction := &versionRecordCorrection{
			docID:          uu.IDv7(),
			version:        docdb.MustVersionTimeFromString("2024-01-01_00-00-01.000"),
			correctedFiles: []string{"doc.json"},
			corrections:    []string{"doc.json: 10 bytes hash-before -> 20 bytes hash-after"},
			addedFiles:     []string{"added.pdf"},
			modifiedFiles:  []string{"modified.pdf"},
			removedFiles:   []string{"removed.pdf"},
		}

		// when
		correction.log(t.Context(), errs.New("commit failed"))

		// then
		messages := decode()
		require.Len(t, messages, 1)
		message := messages[0]
		require.Equal(t, "ERROR", message["level"])
		// The same opening sentence as the successful wording, so one search
		// over the logs finds every correction either way, followed by what
		// distinguishes this one.
		require.Contains(t, message["message"], "Corrected the stored record of a document version to the file content it is restored with")
		require.Contains(t, message["message"], "may be stored in whole or in part, or may have been rolled back")
		require.Contains(t, message["error"], "commit failed")
		// The overwritten values are what the line exists for and are carried
		// unchanged: an uncertain outcome is not a reason to record less.
		require.Equal(t, []any{"doc.json"}, message["correctedFiles"])
		require.Equal(t, []any{"doc.json: 10 bytes hash-before -> 20 bytes hash-after"}, message["corrections"])
		require.Equal(t, []any{"added.pdf"}, message["addedFiles"])
		require.Equal(t, []any{"modified.pdf"}, message["modifiedFiles"])
		require.Equal(t, []any{"removed.pdf"}, message["removedFiles"])
	})
}
