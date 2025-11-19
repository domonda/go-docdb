package testutil

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/domonda/go-errs"
)

var (
	dockerComposeOnce sync.Once
	dockerComposeErr  error
)

// EnsureDockerCompose ensures that docker-compose services are running.
// It uses a sync.Once to ensure services are started only once per test run.
func EnsureDockerCompose() (err error) {
	defer errs.WrapWithFuncParams(&err)

	dockerComposeOnce.Do(func() {
		dockerComposeErr = startDockerCompose()
	})

	return dockerComposeErr
}

func startDockerCompose() (err error) {
	defer errs.WrapWithFuncParams(&err)

	// Find the root directory of go-docdb (where docker-compose.yml is located)
	rootDir, err := findRootDir()
	if err != nil {
		return err
	}

	// Ensure .env file exists
	if err := ensureEnvFile(rootDir); err != nil {
		return err
	}

	// Check if docker-compose is available
	if _, err := exec.LookPath("docker-compose"); err != nil {
		// Try docker compose (newer version)
		if _, err := exec.LookPath("docker"); err != nil {
			return errs.New("docker-compose or docker with compose plugin not found in PATH")
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	// Start docker-compose services
	cmd := exec.CommandContext(ctx, "docker-compose", "up", "-d", "--wait")
	cmd.Dir = rootDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		// Try with "docker compose" (newer syntax)
		cmd = exec.CommandContext(ctx, "docker", "compose", "up", "-d", "--wait")
		cmd.Dir = rootDir
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		if err := cmd.Run(); err != nil {
			return errs.Errorf("failed to start docker-compose: %w", err)
		}
	}

	// Give services a moment to fully initialize
	time.Sleep(2 * time.Second)

	// Initialize the database schema
	if err := initDatabase(rootDir); err != nil {
		return err
	}

	return nil
}

func initDatabase(rootDir string) error {
	initScript := filepath.Join(rootDir, "postgres", "init.sh")

	// Check if init script exists
	if _, err := os.Stat(initScript); err != nil {
		// No init script, skip
		return nil
	}

	// Wait for PostgreSQL to be fully ready to accept connections with the configured user
	if err := waitForPostgres(); err != nil {
		return err
	}

	// Retry database initialization up to 3 times
	var lastErr error
	for attempt := 1; attempt <= 3; attempt++ {
		if attempt > 1 {
			time.Sleep(2 * time.Second)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		cmd := exec.CommandContext(ctx, "bash", initScript)
		cmd.Dir = rootDir
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		if err := cmd.Run(); err != nil {
			lastErr = err
			cancel()
			continue
		}

		cancel()
		return nil
	}

	return errs.Errorf("failed to initialize database after 3 attempts: %w", lastErr)
}

func waitForPostgres() error {
	user := os.Getenv("POSTGRES_USER")
	if user == "" {
		user = "postgres"
	}

	password := os.Getenv("POSTGRES_PASSWORD")
	db := os.Getenv("POSTGRES_DB")
	if db == "" {
		db = "postgres"
	}

	host := os.Getenv("POSTGRES_HOST")
	if host == "" {
		host = "127.0.0.1"
	}

	port := os.Getenv("POSTGRES_PORT")
	if port == "" {
		port = "5432"
	}

	// First, wait for PostgreSQL to accept connections at all (using postgres user with trust auth)
	timeout := time.Now().Add(30 * time.Second)
	postgresReady := false
	for time.Now().Before(timeout) {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		cmd := exec.CommandContext(ctx, "psql",
			"-h", host,
			"-p", port,
			"-U", "postgres",
			"-d", "postgres",
			"-c", "SELECT 1",
		)
		// Use trust auth method since POSTGRES_HOST_AUTH_METHOD=trust in docker-compose
		cmd.Env = os.Environ()

		if err := cmd.Run(); err == nil {
			postgresReady = true
			cancel()
			break
		}
		cancel()

		time.Sleep(1 * time.Second)
	}

	if !postgresReady {
		return errs.New("timeout waiting for PostgreSQL to accept connections")
	}

	// Now ensure the user and database exist
	if user != "postgres" {
		// Create user if it doesn't exist
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		createUserSQL := fmt.Sprintf(
			"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '%s') THEN CREATE USER %s WITH PASSWORD '%s'; END IF; END $$;",
			user, user, password,
		)
		cmd := exec.CommandContext(ctx, "psql",
			"-h", host,
			"-p", port,
			"-U", "postgres",
			"-d", "postgres",
			"-c", createUserSQL,
		)
		cmd.Env = os.Environ()
		cmd.Run() // Ignore error, user might already exist
		cancel()
	}

	// Create database if it doesn't exist
	if db != "postgres" {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		cmd := exec.CommandContext(ctx, "psql",
			"-h", host,
			"-p", port,
			"-U", "postgres",
			"-d", "postgres",
			"-c", fmt.Sprintf("CREATE DATABASE %s;", db),
		)
		cmd.Env = os.Environ()
		cmd.Run() // Ignore error, database might already exist
		cancel()

		// Grant privileges to user
		ctx, cancel = context.WithTimeout(context.Background(), 5*time.Second)
		cmd = exec.CommandContext(ctx, "psql",
			"-h", host,
			"-p", port,
			"-U", "postgres",
			"-d", "postgres",
			"-c", fmt.Sprintf("GRANT ALL PRIVILEGES ON DATABASE %s TO %s;", db, user),
		)
		cmd.Env = os.Environ()
		cmd.Run() // Ignore error
		cancel()
	}

	// Final check: try to connect with the configured user
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "psql",
		"-h", host,
		"-p", port,
		"-U", user,
		"-d", db,
		"-c", "SELECT 1",
	)
	cmd.Env = append(os.Environ(), fmt.Sprintf("PGPASSWORD=%s", password))

	if err := cmd.Run(); err != nil {
		return errs.Errorf("failed to connect to PostgreSQL with user %s: %w", user, err)
	}

	return nil
}

func ensureEnvFile(rootDir string) error {
	envPath := filepath.Join(rootDir, ".env")
	envExamplePath := filepath.Join(rootDir, ".env.example")

	// Check if .env already exists
	if _, err := os.Stat(envPath); err != nil {
		// Copy .env.example to .env
		data, err := os.ReadFile(envExamplePath)
		if err != nil {
			return errs.Errorf("failed to read .env.example: %w", err)
		}

		if err := os.WriteFile(envPath, data, 0644); err != nil {
			return errs.Errorf("failed to create .env: %w", err)
		}
	}

	// Load environment variables from .env file
	return loadEnvFile(envPath)
}

func loadEnvFile(envPath string) error {
	file, err := os.Open(envPath)
	if err != nil {
		return errs.Errorf("failed to open .env file: %w", err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip empty lines and comments
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Parse KEY=VALUE
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		// Only set if not already set in environment
		if os.Getenv(key) == "" {
			os.Setenv(key, value)
		}
	}

	if err := scanner.Err(); err != nil {
		return errs.Errorf("failed to read .env file: %w", err)
	}

	return nil
}

func findRootDir() (string, error) {
	// Start from the current working directory
	dir, err := os.Getwd()
	if err != nil {
		return "", errs.Errorf("failed to get working directory: %w", err)
	}

	// Walk up the directory tree looking for docker-compose.yml
	for {
		dockerComposePath := filepath.Join(dir, "docker-compose.yml")
		if _, err := os.Stat(dockerComposePath); err == nil {
			return dir, nil
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			// Reached the root without finding docker-compose.yml
			return "", errs.New("could not find docker-compose.yml in parent directories")
		}
		dir = parent
	}
}

// StopDockerCompose stops docker-compose services.
// This is typically called in cleanup functions if needed.
func StopDockerCompose() error {
	rootDir, err := findRootDir()
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "docker-compose", "down")
	cmd.Dir = rootDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		// Try with "docker compose" (newer syntax)
		cmd = exec.CommandContext(ctx, "docker", "compose", "down")
		cmd.Dir = rootDir
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		if err := cmd.Run(); err != nil {
			return fmt.Errorf("failed to stop docker-compose: %w", err)
		}
	}

	return nil
}
