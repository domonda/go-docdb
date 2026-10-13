package logcapture

import (
	"io"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/domonda/golog"
	rootlog "github.com/domonda/golog/log"
)

var (
	// capturedLog is the package logger the tests capture.
	capturedLog = rootlog.NewNamedPackageLogger("logcapturetest")

	// otherLog stands in for the logger of another package. It derives from
	// rootlog.Config the way a package logger does, so a capture redirects it
	// too, but it is not registered: the registry accepts one package logger
	// per package path, and this file has only the one.
	otherLog = golog.NewLoggerWithPrefix(golog.NewDerivedConfig(&rootlog.Config), "logcaptureother")
)

// Nothing here calls t.Parallel(), see Start.

func TestStart(t *testing.T) {
	t.Run("Decodes only the lines of the captured package", func(t *testing.T) {
		// given: a capture redirects every package logger of the binary, so
		// a line of another package lands in the same buffer. Counted as the
		// captured package's, it fails an assertion on the number of lines for
		// a reason the assertion does not show.
		decode := Start(t, "logcapturetest")

		// when
		otherLog.Info("from another package").Log()
		capturedLog.Info("from the captured package").Log()

		// then
		messages := decode()
		require.Len(t, messages, 1)
		require.Equal(t, "logcapturetest: from the captured package", messages[0]["message"])
	})

	t.Run("Decodes a line longer than 64 KiB", func(t *testing.T) {
		// given: the length bufio.Scanner refuses by default, and one a log line
		// listing a few hundred files reaches.
		decode := Start(t, "logcapturetest")
		long := strings.Repeat("x", 100*1024)

		// when
		capturedLog.Info("long").Str("value", long).Log()

		// then
		messages := decode()
		require.Len(t, messages, 1)
		require.Equal(t, long, messages[0]["value"])
	})
}

func TestCheckSeesEveryLevel(t *testing.T) {
	// parent stands in for the config Start installs, which lets every level
	// through.
	var parent golog.Config = golog.NewConfig(
		rootlog.Levels,
		rootlog.Levels.Trace.FilterOutBelow(),
		golog.NewJSONWriterConfig(io.Discard, nil),
	)

	t.Run("Accepts a package logger that defers to the capture's filter", func(t *testing.T) {
		// given
		config := golog.NewDerivedConfig(&parent)

		// when
		err := checkSeesEveryLevel(t.Context(), "pkg", config)

		// then
		require.NoError(t, err)
	})

	t.Run("Names the levels a filter of the package logger's own hides", func(t *testing.T) {
		// given: what LOG_LEVEL_PKG_pkg=WARN makes of a package logger. Its own
		// filter replaces the parent's, so a capture of it would never see
		// anything below WARN, and a test asserting that nothing was logged
		// would pass for a correction logged at INFO.
		config := golog.NewDerivedConfigWithFilter(&parent, rootlog.Levels.Warn.FilterOutBelow())

		// when
		err := checkSeesEveryLevel(t.Context(), "pkg", config)

		// then
		require.ErrorContains(t, err, "filters out TRACE, DEBUG, INFO by a filter of its own")
		require.ErrorContains(t, err, "LOG_LEVEL_PKG_pkg")
	})
}
