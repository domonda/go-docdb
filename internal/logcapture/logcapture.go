// Package logcapture collects what one package logger of this process writes
// during a test, so that a log line can be asserted on the way a return value
// is.
package logcapture

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/domonda/go-errs"
	"github.com/domonda/golog"
	rootlog "github.com/domonda/golog/log"
)

// Start captures what the package logger named pkgName writes for the duration
// of one test and returns a function decoding the lines it has written so far.
//
// A package logger derives from the process-wide rootlog.Config (see
// rootlog.NewPackageLogger), and that variable is the only place its output can
// be redirected, so capturing means replacing it: while a capture runs, every
// package logger of the test binary writes into it, at every level. decode
// returns only the lines of pkgName, recognized by the prefix its logger puts
// in front of every message, so a line some other package logs while the code
// under test runs is not counted as one of pkgName's.
//
// Replacing that variable also means a test doing so must not run while another
// one logs, so a caller must not call t.Parallel(). A test that does is held
// back until every sequential one has finished, and a subtest that does is held
// back until its parent's body has returned, so a sequential test has the
// config to itself either way.
//
// Start fails the test when pkgName names no registered package logger, and
// when that logger has a level filter of its own that hides any level. Such a
// filter is never combined with the one the capture installs — a package
// logger with its own filter does not consult its parent's at all (see
// golog.DerivedConfig.IsActive) — so the capture would see less than the code
// logs, and an assertion that nothing was logged would pass because of the
// filter rather than because of the code. LOG_LEVEL_PKG_<pkgName> in the
// environment is how such a filter usually gets there.
func Start(t *testing.T, pkgName string) (decode func() []map[string]any) {
	t.Helper()
	pkgConfig := rootlog.PackageRegistry.ConfigOrNilByPackageName(pkgName)
	if pkgConfig == nil {
		t.Fatalf("logcapture: no package logger named %q is registered", pkgName)
	}

	var buf lockedBuffer
	format := golog.NewDefaultFormat()
	restore := rootlog.Config
	rootlog.Config = golog.NewConfig(
		rootlog.Levels,
		// Everything, so that "nothing was logged" is an assertion about the
		// code rather than about the level filter it ran under.
		rootlog.Levels.Trace.FilterOutBelow(),
		golog.NewJSONWriterConfig(&buf, format),
	)
	t.Cleanup(func() { rootlog.Config = restore })

	// Asked of the package's own config after the swap, so it answers for the
	// filter the package logger actually applies, whichever one that is.
	if err := checkSeesEveryLevel(t.Context(), pkgName, pkgConfig); err != nil {
		t.Fatal(err)
	}

	prefix := fmt.Sprintf(format.PrefixFmt, pkgName, "")
	return func() []map[string]any {
		t.Helper()
		var messages []map[string]any
		// Split by bytes.Lines rather than read by a bufio.Scanner, which
		// refuses a line longer than 64 KiB: a log line listing a few hundred
		// files is that long.
		for line := range bytes.Lines(buf.Bytes()) {
			line = bytes.TrimSpace(line)
			if len(line) == 0 {
				continue
			}
			var message map[string]any
			if err := json.Unmarshal(line, &message); err != nil {
				t.Fatalf("logcapture: captured log line is not JSON: %v, line: %s", err, line)
			}
			if text, _ := message[format.MessageKey].(string); !strings.HasPrefix(text, prefix) {
				continue
			}
			messages = append(messages, message)
		}
		return messages
	}
}

// checkSeesEveryLevel returns an error naming the levels that config, the
// config of the package logger named pkgName, does not let through.
func checkSeesEveryLevel(ctx context.Context, pkgName string, config golog.Config) error {
	var hidden []string
	for _, level := range slices.Sorted(maps.Keys(rootlog.Levels.Names)) {
		if !config.IsActive(ctx, level) {
			hidden = append(hidden, rootlog.Levels.Name(level))
		}
	}
	if len(hidden) == 0 {
		return nil
	}
	return errs.Errorf(
		"logcapture: the package logger %s filters out %s by a filter of its own, which a capture cannot override (is LOG_LEVEL_PKG_%s set?)",
		pkgName, strings.Join(hidden, ", "), pkgName,
	)
}

// lockedBuffer is the writer a capture's loggers write into. A logger can be
// called from any goroutine, and a bytes.Buffer written by two at once is a
// data race.
type lockedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lockedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

// Bytes returns a copy of everything written so far.
func (b *lockedBuffer) Bytes() []byte {
	b.mu.Lock()
	defer b.mu.Unlock()
	return bytes.Clone(b.buf.Bytes())
}
