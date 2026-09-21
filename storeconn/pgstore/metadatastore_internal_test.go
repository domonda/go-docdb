package pgstore

import (
	"bufio"
	"bytes"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/domonda/go-types/uu"
	"github.com/domonda/golog"
	rootlog "github.com/domonda/golog/log"

	"github.com/domonda/go-docdb"
)

// captureLog redirects what this package's logger writes into a buffer for the
// duration of one test and returns a function decoding what was collected.
//
// The package logger derives from the process-wide rootlog.Config (see
// rootlog.NewPackageLogger), so capturing means replacing that variable. A test
// doing so must not run while another one logs, which is why nothing here calls
// t.Parallel(): a test that does is held back until every sequential one has
// finished, so this one has the config to itself.
//
// The correction is also the only thing this package logs at all, so what a
// capture collects is correction lines and nothing else.
func captureLog(t *testing.T) (decode func() []map[string]any) {
	t.Helper()
	var buf bytes.Buffer
	format := *golog.NewDefaultFormat()
	restore := rootlog.Config
	rootlog.Config = golog.NewConfig(
		rootlog.Levels,
		// Everything, so that "nothing was logged" is an assertion about the
		// code rather than about the level filter it ran under.
		rootlog.Levels.Trace.FilterOutBelow(),
		golog.NewJSONWriterConfig(&buf, &format),
	)
	t.Cleanup(func() { rootlog.Config = restore })

	return func() []map[string]any {
		var messages []map[string]any
		scanner := bufio.NewScanner(bytes.NewReader(buf.Bytes()))
		for scanner.Scan() {
			line := bytes.TrimSpace(scanner.Bytes())
			if len(line) == 0 {
				continue
			}
			var message map[string]any
			require.NoError(t, json.Unmarshal(line, &message), "log line: %s", line)
			messages = append(messages, message)
		}
		require.NoError(t, scanner.Err())
		return messages
	}
}

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
		// logs unconditionally after the transaction returned, so the nil
		// receiver is the normal case rather than a defensive check.
		decode := captureLog(t)
		var correction *versionRecordCorrection

		// when
		correction.log(t.Context())

		// then
		require.Empty(t, decode())
	})

	t.Run("Writes what the correction overwrote and what replaced it", func(t *testing.T) {
		// given: the three delta lists carry different values, so a list
		// logged under another list's key is visible here. They are written
		// whenever a correction happens at all, so a version whose own file
		// records were already right has an empty correctedFiles and the delta
		// write as the only thing that happened to it.
		decode := captureLog(t)
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
		correction.log(t.Context())

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
		decode := captureLog(t)
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
		correction.log(t.Context())

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
}
