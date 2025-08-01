package postgres

import (
	"os"
	"testing"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-sqldb"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-sqldb/pqconn"
)

func FixturePostgresMetadataStore(t *testing.T) docdb.MetadataStore {
	t.Helper()
	config := &sqldb.Config{
		Driver:   "postgres",
		Host:     "localhost",
		User:     os.Getenv("POSTGRES_USER"),
		Database: os.Getenv("POSTGRES_DB"),
		Password: os.Getenv("POSTGRES_PASSWORD"),
		Extra:    map[string]string{"sslmode": "disable"},
	}

	conn, err := pqconn.New(t.Context(), config)
	if err != nil {
		t.Fatalf("Failed to connect to postgres, %v", err)
		return nil
	}

	db.SetConn(conn)

	return NewMetadataStore(conn)
}
