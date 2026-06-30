# go-docdb

Copyright (c) 2026 by DOMONDA GmbH

`go-docdb` is an immutable versioned document store. Documents are identified by a UUID and owned by a company UUID. Each document has one or more versions, identified by a `VersionTime` timestamp. Versions are immutable once committed — modifying a document always creates a new version.

## Architecture

The package provides two ways to create a `Conn`:

### 1. Single-store: `localfsdb.Conn`

`localfsdb.NewConn(documentsDir, companiesDir)` stores both file contents and metadata together as a directory hierarchy on the local filesystem. See [localfsdb/README.md](localfsdb/README.md) for full details.

### 2. Split-store: `storeconn.New(DocumentStore, MetadataStore)`

`storeconn.New` composes a separate `DocumentStore` (file contents) and `MetadataStore` (version metadata):

- **`DocumentStore`**: stores and retrieves file content by content hash. Implemented by the `storeconn/s3store` subpackage.
- **`MetadataStore`**: stores and queries version metadata (company, user, reason, file lists). Implemented by the `storeconn/pgstore` subpackage.

> **Note (external data assumption):** when a version's complete file set is not supplied explicitly, `pgstore` reconstructs it from the predecessor plus that version's added/modified/removed lists; the initial (genesis) version has no predecessor, so its full set comes entirely from `added_files`. That an initial version's `added_files` actually holds the document's complete initial file set is a fact of the deployed system that populated the `document_version` table — it is assumed here, and is neither enforced nor verifiable from this repository.

### Global connection

The package maintains a global `Conn` configured once at startup:

```go
docdb.Configure(conn)      // set the global connection
docdb.GetConn()            // retrieve it
```

All package-level functions (e.g. `docdb.CreateDocument(...)`) delegate to the global connection. `Configure` panics if `conn` is nil, and the global connection is guarded by an `RWMutex` so `Configure` and `GetConn` are safe to call concurrently.

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

    RestoreDocument(ctx, doc, recreate) error
}
```

### Read-only connections

`ReadonlyConn` wraps any `Conn` to hand out a read-only view. Read methods pass through to the wrapped connection; every write method returns the `ErrReadonly` sentinel without touching the underlying connection.

```go
ro := docdb.ReadonlyConn(conn)

info, err := ro.LatestDocumentVersionInfo(ctx, docID) // forwarded to conn
err = ro.DeleteDocument(ctx, docID)                   // returns ErrReadonly
```

The write methods (`SetDocumentCompanyID`, `CreateDocument`, `AddDocumentVersion`, `AddMultiDocumentVersion`, `DeleteDocument`, `DeleteDocumentVersion`, `RestoreDocument`) return an error that names the document they refused and wraps `ErrReadonly`. Test for it with `errors.Is(err, docdb.ErrReadonly)`.

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

| Error                        | Description                                        |
| ---------------------------- | -------------------------------------------------- |
| `ErrNoChanges`               | New version is identical to the previous version   |
| `ErrNotImplemented`          | Operation not supported by this `Conn` implementation |
| `ErrReadonly`                | Write method called on a read-only `Conn`          |
| `ErrDocumentNotFound`        | No document with the given ID; also matches `os.ErrNotExist`, `sql.ErrNoRows`, `errs.ErrNotFound` |
| `ErrDocumentFileNotFound`    | File not found in the version                      |
| `ErrDocumentVersionNotFound` | Version not found for the document                 |
| `ErrDocumentAlreadyExists`   | `CreateDocument` called for an existing document ID |
| `ErrVersionAlreadyExists`    | Version timestamp already in use                   |
| `ErrDocumentChanged`         | Optimistic concurrency conflict                    |
| `ErrPathConflict`            | Filesystem path conflict in `localfsdb`            |

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

## Backup & Restore

`HashedDocument` is an in-memory snapshot of a complete document — every version, with file content keyed by content hash:

```go
// Snapshot a document (verifies every file's size and content hash against VersionInfo)
backup, err := docdb.ReadHashedDocument(ctx, conn, docID)

// Validate a HashedDocument before passing it on
err = backup.Validate()

// Restore a document from a HashedDocument backup
err = conn.RestoreDocument(ctx, backup, recreate)
```

`recreate` controls how an existing document on the target conn is handled:

- `recreate=true` — replace: if the document already exists it is deleted first, then recreated entirely from the backup. The on-disk `CompanyID` after the call equals `backup.CompanyID`.
- `recreate=false` — additive merge: the document is created if missing, otherwise existing versions are kept and only the backup versions whose `VersionTime` is not already on disk are added. The on-disk `CompanyID` must equal `backup.CompanyID`, otherwise the call fails without changing anything.

Backends without restore support return wrapped `ErrNotImplemented`.

To copy a document directly from one `Conn` to another, `SyncDocument` combines `ReadHashedDocument` and `Conn.RestoreDocument`:

```go
// Copy a document with all versions and file content from srcConn to destConn
err := docdb.SyncDocument(ctx, srcConn, destConn, docID, recreate)

// Copy all documents of a company from srcConn to destConn
syncedDocIDs, err := docdb.SyncAllCompanyDocuments(ctx, srcConn, destConn, companyID, recreate, continueOnError)
```

The `recreate` flag has the same meaning as for `RestoreDocument`. When `continueOnError` is true, `SyncAllCompanyDocuments` collects per-document errors and keeps going instead of stopping at the first failure; `syncedDocIDs` always lists the documents that synced successfully.

Sync works across any pair of `Conn` implementations, including `localfsdb` and split-store `storeconn` in either direction. Document and company IDs of any UUID version 1-8 are supported on both sides — in particular time-ordered v7 IDs (`uu.IDv7`) are correctly enumerated by `localfsdb`.

## Split-store backends (`storeconn`)

`storeconn.New(documentStore, metadataStore)` builds a `docdb.Conn` from two collaborating backends. The conn owns the orchestration — ordering the two stores' writes, enforcing the "every version keeps at least one file" rule, and rolling back on failure — so each backend only implements storage primitives.

```go
docStore := s3store.NewDocumentStore(bucketName, s3Client) // DocumentStore
metaStore := pgstore.NewMetadataStore()                   // MetadataStore
conn := storeconn.New(docStore, metaStore)
```

### `DocumentStore` — file content by hash

Stores and retrieves file content, keyed by content hash so identical content is deduplicated. The write method returns a `FileInfo` per stored file so the conn can reuse the hash the store computed while writing instead of re-reading the file:

```go
CreateDocumentVersion(ctx, docID, version, files) ([]*docdb.FileInfo, error)
```

It also implements `DocumentExists`, `DocumentHashFileProvider`, `ReadDocumentHashFile`, `DeleteDocument`, `DeleteDocumentHashes`, and `EnumDocumentIDs`. `storeconn/s3store` is the reference implementation; uniqueness of the document ID is enforced by the `MetadataStore`, not here.

### `MetadataStore` — version metadata

Stores and queries version metadata (company, user, reason, file lists, previous version). One method writes a version; the rest are queries plus two deletes:

```go
CreateDocumentVersion(ctx, CreateDocumentVersionInput) (*docdb.VersionInfo, error)
```

`CreateDocumentVersionInput` describes the version to write:

```go
type CreateDocumentVersionInput struct {
    DocID, CompanyID, UserID  uu.ID
    Reason                    string
    NewVersion                docdb.VersionTime
    PreviousVersion           *docdb.VersionTime         // nil => genesis (prev_version NULL)
    AddedFiles, ModifiedFiles []*docdb.FileInfo
    RemovedFiles              []string
    Files                     map[string]docdb.FileInfo  // optional: pre-resolved full file set
}
```

- A nil `PreviousVersion` writes the first (genesis) version: `prev_version` is stored as NULL and every passed file is recorded as added.
- A non-nil `PreviousVersion` appends: the store carries that version's files forward, then applies the added/modified/removed deltas.
- `Files`, when set, is the complete resolved file set. The conn passes it from `AddDocumentVersion`/`RestoreDocument` (which already compute it) so the store skips the predecessor lookup and re-derivation. When nil, the store resolves the set itself from `PreviousVersion` plus the deltas.

`CreateDocumentVersion` never reads file content — `AddedFiles`/`ModifiedFiles` already carry the `FileInfo` (name, size, hash) the `DocumentStore` computed. `storeconn/pgstore` is the reference implementation.

### Blob-only migration (versions-exist mode)

`pgstore.ContextWithMetadataStoreVersionsExist(ctx)` switches the Postgres `MetadataStore` into versions-exist mode, where it is immutable: it verifies versions instead of inserting them and verifies existence instead of deleting. It exists for one job — copying a document's file blobs to a *different* `DocumentStore` while reusing a `MetadataStore` that already holds the versions (for example moving blobs to a new S3 bucket without rewriting Postgres):

```go
// Same shared Postgres metadata, new blob store.
dest := storeconn.New(newDocStore, sharedMetaStore)

// In versions-exist mode the metadata is read and verified, never mutated.
ctx = pgstore.ContextWithMetadataStoreVersionsExist(ctx)

// Drives newDocStore to write the blobs; verifies each version against the
// shared metadata instead of re-inserting it.
err := docdb.SyncDocument(ctx, srcConn, dest, docID, false)
```

In this mode:

- `CreateDocumentVersion` inserts nothing; it errors if the stored version is missing or any field differs from what it would have written.
- `DeleteDocument` / `DeleteDocumentVersion` delete nothing; they verify existence (returning `ErrDocumentNotFound` if missing). `DeleteDocumentVersion` still reports the same leftover versions and blob hashes a real delete would, so the caller can clean up the `DocumentStore`.
- The shared metadata is never mutated, even when a copy fails and rolls back.

## Debugging

`DebugPrintDocument` and `DebugPrintCompanyDocuments` print a human-readable, indented tree of a document — or of all documents of a company — to standard output, useful for inspecting versions and files during development:

```go
// Print one document: a header, every version, and the files of each version
err := docdb.DebugPrintDocument(ctx, conn, docID, "", "  ")

// Print every document of a company (header + each document's tree)
err := docdb.DebugPrintCompanyDocuments(ctx, conn, companyID, "", "  ")
```

`linePrefix` is prepended to every line and `indent` is added once per tree level (document → version → file). Within each version, files are printed sorted by name. `DebugPrintCompanyDocuments` prints documents in `EnumCompanyDocumentIDs` enumeration order, which is not necessarily sorted. Example layout:

```
Document: 0c4e8f2a-…  Company: 7b1d…  Versions: 2
  Version: 2024-11-15_09-00-00.000  User: 3f2a…  Reason: "initial upload"
    File: invoice.pdf  Size: 12345  Hash: 1f8ac…
  Version: 2024-11-16_10-30-00.000  User: 3f2a…  Reason: "added OCR result"
    File: invoice.pdf  Size: 12345  Hash: 1f8ac…
    File: ocr.json     Size: 678    Hash: 9b3de…
```

## Testing Helpers

- `localfsdb.NewTestConn(t)` — creates a `localfsdb.Conn` in a temp directory, cleaned up after the test
- `MockConn` — struct with function fields for each `Conn` method, for use in unit tests
- `NewConnWithError(err)` — returns a `Conn` that returns the given error from every method (used as the default global connection before `Configure` is called)

## Subpackages

| Package             | Description                                        |
| ------------------- | -------------------------------------------------- |
| `localfsdb`         | Filesystem-based `Conn` storing files and metadata together (see [localfsdb/README.md](localfsdb/README.md)) |
| `storeconn`         | Split-store `Conn` composing a `DocumentStore` and `MetadataStore` (see [storeconn/README.md](storeconn/README.md)) |
| `storeconn/s3store` | `DocumentStore` implementation backed by AWS S3    |
| `storeconn/pgstore` | `MetadataStore` backed by PostgreSQL; supports an immutable versions-exist mode via `ContextWithMetadataStoreVersionsExist` |
| `routerconn`        | Routing `Conn` selecting a backend per document via a callback |
| `integrationtests`  | Shared integration test suite runnable against any `Conn` implementation |
