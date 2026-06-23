# Changelog

All notable changes to `github.com/domonda/go-docdb` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.7.0] - 2026-06-23

### Added
- `SyncDocument` and `SyncAllCompanyDocuments`: copy a document — or every document of a company — with all versions and file content between any two `Conn` implementations. `SyncAllCompanyDocuments` takes a `continueOnError` flag to collect per-document failures instead of stopping at the first error.
- `Conn.RestoreDocument` is now implemented for `localfsdb` and the split-store `storeconn` (previously `ErrNotImplemented` stubs), restoring a document from a `HashedDocument` backup. Added `(*HashedDocument).Validate()` to check a backup before restoring.
- `DebugPrintDocument` and `DebugPrintCompanyDocuments`: print a human-readable, indented tree of a document (or all documents of a company) to standard output — every version and its files, with the files of each version sorted by name — for quick inspection during development. See the Debugging section in the README.
- `ErrPathConflict`: `localfsdb.CreateDocument` now reports filesystem path conflicts with full disk-state diagnostics (document/company IDs, paths, entry type, size, mtime) instead of an opaque "file already exists" error.
- `localfsdb` enumerates document and company IDs of any UUID version 1-8, including time-ordered v7 (`uu.IDv7`).

### Changed
- Split-store support moved into a new `storeconn` package: `docdb.NewConn` → `storeconn.New`, `docdb.DocumentStore` → `storeconn.DocumentStore`, `docdb.MetadataStore` → `storeconn.MetadataStore`, and the backends `s3` → `storeconn/s3store` and `postgres` → `storeconn/pgstore`. The `docdb` package now only defines the `Conn` interface and shared types.
- `proxyconn` rewritten as `routerconn`: the `ConfigMap`/`ConnType` model is replaced by routing callbacks (`connForCompanyID`, `connForDocID`), and `EnumDocumentIDs` is now implemented, deduplicating document IDs across all backends.
- The S3 `DocumentStore` now returns typed errors (`ErrDocumentFileNotFound`, `ErrDocumentNotFound`); `NewS3DocumentStore` → `NewDocumentStore`, `FileProviderFromS3Keys` → `FileProviderFromKeys`, and the public `s3.ErrNoSuchFile` sentinel was removed.
- `Conn.RestoreDocument`'s parameter was renamed `merge` → `recreate` (semantics inverted): `recreate=true` replaces an existing document, `recreate=false` adds only the backup's missing versions to a document that must match the backup's company.
- `Configure` now guards the global connection with a `sync.RWMutex` and panics on a nil `Conn`.
- Bumped the Go toolchain to 1.26.

### Fixed
- `localfsdb.CreateDocument` is now race-safe under concurrent imports (go-fs bump), eliminating spurious "file already exists" errors when documents share UUID-prefix parent directories.
- `DeleteDocumentVersion` (Postgres) no longer deletes file blobs that sibling versions still reference, and no longer falsely raises `ErrDocumentNotFound` after a successful delete.
- `RestoreDocument` merge mode can now restore a deleted middle version instead of rejecting it.
- `ReadHashedDocument` now errors clearly when storage and version metadata disagree about a file, instead of reporting "expected 0 bytes" or silently skipping it.

### Removed
- The Postgres `Postgres*` document-version helper functions (app-specific glue exposing the internal `document_version` key) moved to domonda-service; the unused `ToRefactorVersionExists` was dropped.

## [v0.6.3] - 2026-04-20

### Added
- `logconn`: logging adapter for `docdb.Conn` with a configurable `golog.Logger`.

### Fixed
- `conn`: use `cmp.Or` for password retrieval from the `PGPASSWORD` environment variable.

## [v0.6.2] - 2026-03-31

### Changed
- Update `go-sqldb` to v1.0.1 and migrate to its new API.
- Update `jsonparser` to v1.1.2.

## [v0.6.1] - 2026-03-24

### Fixed
- `versioninfo`: treat an empty `PrevVersion` string as `nil` when unmarshaling JSON.

## [v0.6.0] - 2026-03-18

### Changed
- Make `AddDocumentVersion` atomic: persist the full file set and wrap inserts in a transaction.
- `DocumentVersions` returns `ErrDocumentNotFound` when the document does not exist.
- Pass `context` through `documentVersionInfo` and `newVersionInfo` instead of using `context.Background()`.

### Fixed
- Numerous bug fixes, typos, and code-quality cleanups across `docdb` and subpackages.

### Documentation
- Add doc comments to `VersionInfo`, its fields, and methods.
- Update README for the root package and the `localfsdb` subpackage; fix stale `RFC3339Nano` references.

## [v0.5.2] - 2026-03-16

### Added
- `CreateVersionResult.Validate` and enforcement of `WriteFiles`/`RemoveFiles` disjointness.

## [v0.5.1] - 2026-03-12

### Fixed
- `AddMultiDocumentVersion` skips `ErrNoChanges` per document instead of failing the whole batch.

## [v0.5.0] - 2026-03-12

### Added
- `docID` parameter to `CreateVersionFunc` and `AddMultiDocumentVersion`.

### Changed
- Use `db.Exec(ctx, …)` instead of `tx.Exec(…)`.

## [v0.4.1] - 2026-02-19

### Changed
- Refactor the PostgreSQL schema for document versioning.
- Rename `VersionTime.PrettyPrint` to `PrettyString`.
- Update `go-errs` to v1.0.0.
- CI: update `actions/checkout` v5 → v6.

### Fixed
- `schema`: fix a typo, a wrong comment target, and array syntax in `document_version.sql`.
- `schema`: add missing `if not exists` in the `version_time` domain creation.

## [v0.4.0] - 2025-11-27

### Changed
- `CreateVersionFunc` returns a `CreateVersionResult` instead of multiple values.

## [v0.3.0] - 2025-11-27

### Changed
- `CreateVersionFunc` returns the new version timestamp.

## [v0.2.1] - 2025-11-27

### Fixed
- Roll back the new version when the `onNewVersion` callback fails.

## [v0.2.0] - 2025-11-24

### Added
- S3 document store implementation.
- `FileProvider` implementations: `fileReaderProvider` and `memFileProvider`.

### Changed
- Explicitly pass the new version timestamp to `CreateDocument` and `AddDocumentVersion`.
- PostgreSQL configuration and schema create schemas, tables, and indexes only if they do not already exist.

### Removed
- `hashdb` package and sub-module definitions.

## [v0.1.0] - 2025-11-18

Initial release.

### Added
- Core `docdb` package with `Conn` for document storage and versioning.
- `CreateDocument` with an `OnNewVersionFunc` callback that can roll back the new version.
- `AddDocumentVersion` with an `onNewVersion` callback and explicit version times.
- `localfsdb` local filesystem backend, including its directory/versioning README.
- `FileProvider` abstraction with `ExtFileProvider`, `RemoveFileProvider`, `MockFileProvider`, and `ListFiles`.
- `ReadDocument`, `BackupDocument`, `RestoreDocument` (with `HashedDocument`), `ReadMemFile`, and `TempFileCopy`.
- `ProxyConn` and `DeprecatedConn` (holding deprecated check-out/in methods).
- `VersionInfo` with `CompanyID`, `LatestDocumentVersionInfo`, and `VersionTime.SetNull`.

[v0.7.0]: https://github.com/domonda/go-docdb/releases/tag/v0.7.0
[v0.6.3]: https://github.com/domonda/go-docdb/releases/tag/v0.6.3
[v0.6.2]: https://github.com/domonda/go-docdb/releases/tag/v0.6.2
[v0.6.1]: https://github.com/domonda/go-docdb/releases/tag/v0.6.1
[v0.6.0]: https://github.com/domonda/go-docdb/releases/tag/v0.6.0
[v0.5.2]: https://github.com/domonda/go-docdb/releases/tag/v0.5.2
[v0.5.1]: https://github.com/domonda/go-docdb/releases/tag/v0.5.1
[v0.5.0]: https://github.com/domonda/go-docdb/releases/tag/v0.5.0
[v0.4.1]: https://github.com/domonda/go-docdb/releases/tag/v0.4.1
[v0.4.0]: https://github.com/domonda/go-docdb/releases/tag/v0.4.0
[v0.3.0]: https://github.com/domonda/go-docdb/releases/tag/v0.3.0
[v0.2.1]: https://github.com/domonda/go-docdb/releases/tag/v0.2.1
[v0.2.0]: https://github.com/domonda/go-docdb/releases/tag/v0.2.0
[v0.1.0]: https://github.com/domonda/go-docdb/releases/tag/v0.1.0
