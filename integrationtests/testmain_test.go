package integrationtests

import (
	"fmt"
	"os"
	"testing"

	"github.com/domonda/go-docdb/internal/testutil"
)

func TestMain(m *testing.M) {
	// Ensure docker-compose services are running
	if err := testutil.EnsureDockerCompose(); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to start docker-compose: %v\n", err)
		os.Exit(1)
	}

	// Run tests
	os.Exit(m.Run())
}
