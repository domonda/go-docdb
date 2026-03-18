# go-docdb

Copyright (c) 2026 by DOMONDA GmbH

`go-docdb` is an immutable versioned document store. Documents are identified by a UUID and owned by a company UUID. Each document has one or more versions, identified by a `VersionTime` timestamp. Versions are immutable once committed — modifying a document always creates a new version.

## Architecture

The package provides two ways to create a `Conn`:

### 1. Single-store: `localfsdb.Conn`

`localfsdb.NewConn(documentsDir, companiesDir)` stores both file contents and metadata together as a directory hierarchy on the local filesystem. See [localfsdb/README.md](localfsdb/README.md) for full details.

### 2. Split-store: `docdb.NewConn(DocumentStore, MetadataStore)`

`docdb.NewConn` composes a separate `DocumentStore` (file contents) and `MetadataStore` (version metadata):

- **`DocumentStore`**: stores and retrieves file content by content hash. Implemented by the `s3/` subpackage.
- **`MetadataStore`**: stores and queries version metadata (company, user, reason, file lists). Implemented by the `postgres/` subpackage.

### Global connection

The package maintains a global `Conn` configured once at startup:

```go
docdb.Configure(conn)      // set the global connection
docdb.GetConn()            // retrieve it
```

All package-level functions (e.g. `docdb.CreateDocument(...)`) delegate to the global connection.

## Core Types

### `VersionTime`

A UTC timestamp truncated to millisecond precision, used to identify a document version. Format: `2006-01-02_15-04-05.000`.

```go
v := docdb.NewVersionTime()                          // current time
v, err := docdb.VersionTimeFromString("2024-11-15_09-00-00.000")
err = v.Validate()  // returns error for zero value
v.After(other), v.Before(other), v.Equal(other)
```

Implements `database/sql.Scanner`, `driver.Valuer`, and `encoding.TextMarshaler`/`TextUnmarshaler`.

### `VersionInfo`

Metadata for a single document version:

```go
type VersionInfo struct {
    CompanyID    uu.ID
    DocID        uu.ID
    Version      VersionTime
    PrevVersion  *VersionTime  // nil if first version
    CommitUserID uu.ID
    CommitReason string

    Files         map[string]FileInfo  // all files and their hashes in this version
    AddedFiles    []string             // files new in this version
    RemovedFiles  []string             // files removed from previous version
    ModifiedFiles []string             // files changed from previous version
}
```

### `FileInfo`

```go
type FileInfo struct {
    Name string
    Size int64
    Hash string   // Dropbox-compatible content hash (64 hex characters)
}
```

File content is identified by a Dropbox-compatible content hash (see `ContentHash(data []byte) string`).

### `FileProvider`

Read-only interface for accessing files within a version:

```go
type FileProvider interface {
    HasFile(filename string) (bool, error)
    ListFiles(ctx context.Context) ([]string, error)
    ReadFile(ctx context.Context, filename string) ([]byte, error)
}
```

Helper constructors:
- `DirFileProvider(dir)` — backed by a filesystem directory
- `NewFileProvider(files ...fs.FileReader)` — backed by in-memory file readers
- `ExtFileProvider(base, extFiles...)` — extends a base provider with additional files
- `RemoveFileProvider(base, filenames...)` — wraps a base provider and hides named files
- `SingleMemFileProvider(file)` — single in-memory file
- `ReadMemFile(ctx, provider, filename)` — reads a file from a provider as `fs.MemFile`
- `TempFileCopy(ctx, provider, filename)` — reads a file to a temp file on disk

## `Conn` Interface

```go
type Conn interface {
    DocumentExists(ctx, docID) (bool, error)
    EnumDocumentIDs(ctx, callback) error
    EnumCompanyDocumentIDs(ctx, companyID, callback) error

    DocumentCompanyID(ctx, docID) (companyID, error)
    SetDocumentCompanyID(ctx, docID, companyID) error

    DocumentVersions(ctx, docID) ([]VersionTime, error)
    LatestDocumentVersion(ctx, docID) (VersionTime, error)
    DocumentVersionInfo(ctx, docID, version) (*VersionInfo, error)
    LatestDocumentVersionInfo(ctx, docID) (*VersionInfo, error)
    DocumentVersionFileProvider(ctx, docID, version) (FileProvider, error)
    ReadDocumentVersionFile(ctx, docID, version, filename) ([]byte, error)

    CreateDocument(ctx, companyID, docID, userID, reason, version, files, onNewVersion) error
    AddDocumentVersion(ctx, docID, userID, reason, createVersion, onNewVersion) error
    AddMultiDocumentVersion(ctx, docIDs, userID, reason, createVersion, onNewVersion) error

    DeleteDocument(ctx, docID) error
    DeleteDocumentVersion(ctx, docID, version) (leftVersions []VersionTime, error)

    RestoreDocument(ctx, doc, merge) error
}
```

## Creating and Versioning Documents

### Creating a document

```go
files := []fs.FileReader{fs.NewMemFile("invoice.pdf", pdfData)}

var versionInfo *docdb.VersionInfo
err := conn.CreateDocument(
    ctx,
    companyID,
    docID,
    userID,
    "initial upload",
    docdb.NewVersionTime(),
    files,
    docdb.CaptureNewVersionInfo(&versionInfo),
)
```

If `onNewVersion` returns an error or panics, the entire document creation is atomically rolled back.

### Adding a version

`AddDocumentVersion` uses a `CreateVersionFunc` callback that receives the previous version and its files, and returns a `CreateVersionResult`:

```go
type CreateVersionResult struct {
    Version      VersionTime     // must be after previous version
    WriteFiles   []fs.FileReader // files to add or overwrite
    RemoveFiles  []string        // filenames to remove
    NewCompanyID uu.NullableID   // optional: change the owning company
}
```

If `createVersion` or `onNewVersion` returns an error or panics, the version creation is rolled back. Returns `ErrNoChanges` if the resulting file set is identical to the previous version.

**Convenience helpers for common cases:**

```go
// Add or overwrite files (no removals)
err := conn.AddDocumentVersion(ctx, docID, userID, "added OCR result",
    docdb.CreateVersionWriteFiles(fs.NewMemFile("ocr.json", data)),
    docdb.CaptureNewVersionInfo(&versionInfo))

// Remove files
err := conn.AddDocumentVersion(ctx, docID, userID, "removed attachment",
    docdb.CreateVersionRemoveFiles("attachment.pdf"),
    docdb.CaptureNewVersionInfo(&versionInfo))
```

### Adding a version to multiple documents atomically

```go
err := conn.AddMultiDocumentVersion(ctx, docIDs, userID, reason, createVersion, onNewVersion)
```

Documents with no file changes are silently skipped. Returns `ErrNoChanges` only if no document was changed at all. On any error, all already-created versions are rolled back via `DeleteDocumentVersion`.

## Error Types

| Error | Description |
|---|---|
| `ErrNoChanges` | New version is identical to the previous version |
| `ErrNotImplemented` | Operation not supported by this `Conn` implementation |
| `ErrDocumentNotFound` | No document with the given ID; also matches `os.ErrNotExist`, `sql.ErrNoRows`, `errs.ErrNotFound` |
| `ErrDocumentFileNotFound` | File not found in the version |
| `ErrDocumentVersionNotFound` | Version not found for the document |
| `ErrDocumentAlreadyExists` | `CreateDocument` called for an existing document ID |
| `ErrVersionAlreadyExists` | Version timestamp already in use |
| `ErrDocumentChanged` | Optimistic concurrency conflict |

Use `errs.Has[ErrDocumentNotFound](err)` (from `github.com/domonda/go-errs`) to test for a specific error type.

## Utility Functions

```go
// Copy all version files of a document to a backup directory
destDocDir, err := docdb.CopyDocumentFiles(ctx, conn, docID, backupDir, overwrite)

// Copy all documents of a company to a backup directory
docDirs, err := docdb.CopyAllCompanyDocumentFiles(ctx, conn, companyID, backupDir, overwrite)

// Resolve a deleted version to the next available version
validVersion, err := docdb.SubstituteDeletedDocumentVersion(ctx, docID, deletedVersion)
```

## Testing Helpers

- `localfsdb.NewTestConn(t)` — creates a `localfsdb.Conn` in a temp directory, cleaned up after the test
- `MockConn` — struct with function fields for each `Conn` method, for use in unit tests
- `NewConnWithError(err)` — returns a `Conn` that returns the given error from every method (used as the default global connection before `Configure` is called)

## Subpackages

| Package | Description |
|---|---|
| `localfsdb` | Filesystem-based `Conn` storing files and metadata together (see [localfsdb/README.md](localfsdb/README.md)) |
| `s3` | `DocumentStore` implementation backed by AWS S3 |
| `postgres` | `MetadataStore` and read-only `MetadataStore` implementations backed by PostgreSQL |
| `proxyconn` | `Conn` decorator/proxy |
| `integrationtests` | Shared integration test suite runnable against any `Conn` implementation |
