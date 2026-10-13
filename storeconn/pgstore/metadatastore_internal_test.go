package pgstore

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/internal/logcapture"
)

// TestVersionRecordCorrectionLog covers the line reporting a corrected version.
//
// The record of a correction is its docdb.document_version_correction row; the
// line is how an operator learns that a correction happened at all, and names
// that row by its id. A field logged under the wrong key sends whoever reads it
// to the wrong file or the wrong list, and nothing downstream would notice.
func TestVersionRecordCorrectionLog(t *testing.T) {
	t.Run("Writes nothing for a version that needed no correction", func(t *testing.T) {
		// given: the nil correction CreateDocumentVersion holds for every
		// version it did not have to correct, which is almost all of them. It
		// logs unconditionally after the transaction returned, whether that
		// transaction failed or not, so the nil receiver is the normal case
		// rather than a defensive check — and a failed call that corrected
		// nothing must stay silent about corrections.
		decode := logcapture.Start(t, "pgstore")
		var correction *versionRecordCorrection

		// when
		correction.log(t.Context(), nil)
		correction.log(t.Context(), errs.New("commit failed"))

		// then
		require.Empty(t, decode())
	})

	t.Run("Writes what the correction overwrote, what replaced it, and its row", func(t *testing.T) {
		// given: the three delta lists carry different values, so a list
		// logged under another list's key is visible here.
		decode := logcapture.Start(t, "pgstore")
		correction := &versionRecordCorrection{
			id: uu.IDv7(),
			version: &docdb.VersionInfo{
				DocID:         uu.IDv7(),
				Version:       docdb.MustVersionTimeFromString("2024-01-01_00-00-01.000"),
				AddedFiles:    []string{"added.pdf"},
				ModifiedFiles: []string{"modified.pdf"},
				RemovedFiles:  []string{"removed.pdf"},
			},
			correctedFiles: []string{"doc.json"},
			corrections:    []string{"doc.json: 10 bytes hash-before -> 20 bytes hash-after"},
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
		require.NotContains(t, message, "error")
		require.Equal(t, correction.id.String(), message["correctionID"])
		require.Equal(t, correction.version.DocID.String(), message["docID"])
		require.Equal(t, correction.version.Version.String(), message["version"])
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
		// written and still has to carry the deltas, or a correction of the
		// delta lists alone is invisible to anyone reading the logs.
		decode := logcapture.Start(t, "pgstore")
		correction := &versionRecordCorrection{
			id: uu.IDv7(),
			version: &docdb.VersionInfo{
				DocID:         uu.IDv7(),
				Version:       docdb.MustVersionTimeFromString("2024-01-01_00-00-01.000"),
				AddedFiles:    []string{"added.pdf"},
				ModifiedFiles: []string{"modified.pdf"},
				RemovedFiles:  []string{"removed.pdf"},
			},
			correctedFiles: []string{},
			corrections:    []string{},
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

	t.Run("Reports a correction whose transaction failed as stored only if its row is", func(t *testing.T) {
		// given: a correction that was written and whose transaction then
		// returned an error. The error does not mean the correction is gone —
		// a COMMIT the server applied but could not acknowledge keeps it, and
		// so does a released savepoint in a transaction the caller still
		// commits (see versionRecordCorrection). Dropping the line would hide
		// a correction in precisely those cases, so it is written, and says
		// where to look for whether it was kept: the row is written by the
		// same statement as the correction and exists exactly when it does.
		decode := logcapture.Start(t, "pgstore")
		correction := &versionRecordCorrection{
			id: uu.IDv7(),
			version: &docdb.VersionInfo{
				DocID:      uu.IDv7(),
				Version:    docdb.MustVersionTimeFromString("2024-01-01_00-00-01.000"),
				AddedFiles: []string{"doc.json"},
			},
			correctedFiles: []string{"doc.json"},
			corrections:    []string{"doc.json: 10 bytes hash-before -> 20 bytes hash-after"},
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
		require.Contains(t, message["message"], "it is stored if and only if docdb.document_version_correction holds the row named by correctionID")
		require.Contains(t, message["error"], "commit failed")
		require.Equal(t, correction.id.String(), message["correctionID"])
		require.Equal(t, []any{"doc.json"}, message["correctedFiles"])
		require.Equal(t, []any{"doc.json: 10 bytes hash-before -> 20 bytes hash-after"}, message["corrections"])
	})
}
