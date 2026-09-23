// Package logcapture collects what the loggers of this process write during one
// test, so that a log line can be asserted on the way a return value is.
package logcapture

import (
	"bufio"
	"bytes"
	"encoding/json"
	"testing"

	"github.com/domonda/golog"
	rootlog "github.com/domonda/golog/log"
)

// Start redirects what the loggers of this process write into a buffer for the
// duration of one test and returns a function decoding what was collected.
//
// A package logger derives from the process-wide rootlog.Config (see
// rootlog.NewPackageLogger), so capturing means replacing that variable: every
// package linked into the test binary is redirected, not only the one under
// test, and a test counting lines has to expect whatever its dependencies log
// as well.
//
// Replacing that variable also means a test doing so must not run while another
// one logs, so a caller must not call t.Parallel(). A test that does is held
// back until every sequential one has finished, and a subtest that does is held
// back until its parent's body has returned, so a sequential test has the
// config to itself either way.
func Start(t *testing.T) (decode func() []map[string]any) {
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
		t.Helper()
		var messages []map[string]any
		scanner := bufio.NewScanner(bytes.NewReader(buf.Bytes()))
		for scanner.Scan() {
			line := bytes.TrimSpace(scanner.Bytes())
			if len(line) == 0 {
				continue
			}
			var message map[string]any
			if err := json.Unmarshal(line, &message); err != nil {
				t.Fatalf("captured log line is not JSON: %v, line: %s", err, line)
			}
			messages = append(messages, message)
		}
		if err := scanner.Err(); err != nil {
			t.Fatalf("failed to read the captured log: %v", err)
		}
		return messages
	}
}
