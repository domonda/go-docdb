# Changelog

All notable changes to `github.com/domonda/go-docdb` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.8.1] - 2026-06-29

### Fixed
- `s3store` no longer silently caps document operations at 1000 objects. `DeleteDocument`, `DeleteDocumentHashes`, and `DocumentHashFileProvider` each previously issued a single `ListObjectsV2` call — which AWS S3 limits to 1000 keys per response — so a document with more than 1000 stored objects had its extra files silently skipped: a delete would leave objects behind, and a hash lookup would miss files. All three now page through every object under the document prefix via the AWS SDK `ListObjectsV2` paginator, and deletes are split into batches of at most 1000 keys to stay within the `DeleteObjects` limit. `DeleteDocument` lists and deletes one page at a time, so memory stays bounded by a single page even for very large documents.
- `s3store` delete paths now surface the per-object failures S3 reports inside an otherwise-successful (HTTP 200) `DeleteObjects` response instead of ignoring them. S3 does not return these as a transport error, so a partial delete failure was previously swallowed and could leave objects behind without any error; the delete now fails loudly. The same check is applied to the test bucket teardown so a failed cleanup no longer surfaces later as a confusing `BucketNotEmpty`.

### Added
- `s3store.DeleteObjectsErr`: exported helper that converts the per-object `Errors` of an `awss3.DeleteObjectsOutput` into a Go error (and returns nil for a nil output or no failures), so callers performing their own `DeleteObjects` calls can detect the silent per-object failures S3 hides in a 200 response.
- `storeconn/README.md`: documents the split-store `Conn` — how `New` composes a `DocumentStore` and `MetadataStore`, how the content hash joins them, and how the orchestration layer keeps the two backends consistent (ordering and compensating rollback) without a distributed transaction.

### Changed
- `s3store.EnumDocumentIDs` is reimplemented on top of the AWS SDK `ListObjectsV2` paginator, replacing the hand-rolled continuation-token enumerator. Behavior is unchanged: every object in the bucket is scanned across all pages and each unique document ID is reported to the callback exactly once.
- Updated `aws-sdk-go-v2` (`service/s3` to v1.104.0, core to v1.42.0) and the remaining module dependencies to their current releases.

## [v0.8.0] - 2026-06-26

### Added
- `docdb.VersionInfo.Equal`: reports whether two `VersionInfo`s describe the same committed version — scalar metadata, the resolved file set (`EqualFiles`), and the added/removed/modified filename lists compared order-insensitively. The Postgres versions-exist check uses it, so a field added to `VersionInfo` is compared automatically instead of being missed by a hand-rolled field-by-field check.
- `ReadonlyConn`: wrap any `Conn` to hand out a read-only view. Read methods pass through to the wrapped connection; every write method (`SetDocumentCompanyID`, `CreateDocument`, `AddDocumentVersion`, `AddMultiDocumentVersion`, `DeleteDocument`, `DeleteDocumentVersion`, `RestoreDocument`) returns the new `ErrReadonly` sentinel without touching the underlying connection. Each write error names the document it refused, and `errors.Is(err, docdb.ErrReadonly)` matches.
- `pgstore.ContextWithMetadataStoreVersionsExist`: derives a context that switches the Postgres `MetadataStore` into versions-exist mode, treating it as immutable. `CreateDocumentVersion` inserts nothing and instead verifies the already-stored version is identical to what would have been inserted; `DeleteDocument` and `DeleteDocumentVersion` delete nothing and instead verify existence (`DeleteDocumentVersion` still reports the same left-over versions and blob hashes a real delete would, so the caller can clean up the `DocumentStore`). All three return an error if the version or document is missing, and `CreateDocumentVersion` additionally errors if any stored field differs from what it would have inserted. Intended for copying a document to a different `DocumentStore` while reusing a `MetadataStore` that already holds the versions (for example migrating only the file blobs to a new `DocumentStore`): the shared metadata is read and verified, never mutated, even on rollback.

### Changed
- Split-store API unification: `storeconn.MetadataStore`'s `CreateDocument` + `AddDocumentVersion` collapse into a single `CreateDocumentVersion(ctx, CreateDocumentVersionInput)`, and `DocumentStore.CreateDocument` is replaced by `CreateDocumentVersion(ctx, docID, version, files)`. The `CreateDocumentVersionInput.PreviousVersion` field is a `*VersionTime`: a nil value creates the first (genesis) version with `prev_version` stored as NULL, fixing a zero-`VersionTime` insert failure when adding a version that precedes a document's existing versions.
- `storeconn.DocumentStore.CreateDocumentVersion` now returns `[]*docdb.FileInfo` (name, size, content hash) for each stored file, in input order, alongside its error. The store already computes the content hash while writing each blob, so returning it lets the split-store genesis path (`CreateDocument`) reuse those `FileInfo`s instead of re-reading and re-hashing every file — halving file I/O and hashing on document creation.
- `storeconn.CreateDocumentVersionInput` gains an optional `Files` field holding the complete resolved file set of the new version. `AddDocumentVersion` and `RestoreDocument` already compute it, so they now pass it through and the Postgres `MetadataStore` uses it directly — skipping the extra `DocumentVersionInfo` query for the previous version and the redundant carry-forward + delta re-derivation on every appended/restored version. When `Files` is nil the store still derives the set from `PreviousVersion` plus the added/modified/removed lists.

### Fixed
- `storeconn` merge-restore (`RestoreDocument` with `recreate=false`) now stores `prev_version` as NULL for a restored version that precedes the document's existing versions, instead of passing a zero `VersionTime` and failing with "invalid zero VersionTime". This is the case the genesis-NULL change above was meant to cover; the split-store conn now actually passes a nil `previousVersion` for the earliest restored version.
- The split-store genesis path (`CreateDocument`) cleans up a failed create without orphaning blobs or destroying unrelated data. Because the up-front existence check proves the `DocumentStore` held no files for the document, the rollback deletes the whole document's blobs — which also removes objects left by a partial blob write that returned no `FileInfo`s — except when the metadata insert failed with `ErrDocumentAlreadyExists`. That error is exactly what disproves the existence check under concurrency: a concurrent `CreateDocument` (or a pre-existing metadata-without-blobs document being re-created) owns those content-addressed blobs, so deleting them would corrupt the winner; the identical objects are left in place instead. The metadata rollback deletes only the single version this call inserted (and only when it was inserted), targeting it with `DeleteDocumentVersion` rather than `DeleteDocument`, so a document that already holds versions in the `MetadataStore` (a fresh `DocumentStore` reusing a populated `MetadataStore`, or an inconsistent metadata-without-blobs state) is never wiped.
- The split-store `CreateDocument` now rolls back (and correctly reports) when its `onNewVersion` callback fails or the call panics. Inlining its helper had left it with an unnamed error return, so the deferred rollback and panic recovery silently saw a `nil` error: an `onNewVersion` failure left the genesis document committed, a recovered panic was reported as success, and rollback-cleanup errors were dropped. The error return is named again.
- `pgstore.MetadataStore.CreateDocumentVersion` maps a Postgres unique violation to `ErrDocumentAlreadyExists` for a genesis insert and `ErrVersionAlreadyExists` for an appended version, instead of leaking the raw driver error.
- The Postgres schema adds a partial unique index (`document_version_one_genesis_per_document_idx` on `(document_id) where prev_version is null`) enforcing at most one genesis version per document. This closes a gap where a document whose metadata existed but whose blobs were absent could be silently given a second genesis version with a different timestamp: the insert now raises a unique violation that `CreateDocumentVersion` maps to `ErrDocumentAlreadyExists`. Production schemas need the same index added by migration.
- `pgstore.MetadataStore.CreateDocumentVersion` now returns a not-found error when its non-nil `previousVersion` is missing from the `MetadataStore`, instead of silently dropping the carried-forward files (which would persist a version missing those files, or cause a confusing file-set mismatch in versions-exist mode).
- The split-store `CreateDocument` now refuses an already-existing document with `ErrDocumentAlreadyExists` (honoring the documented `Conn.CreateDocument` contract) before writing anything. Previously it proceeded, and on a later failure the genesis rollback could delete file blobs (deduplicated by content hash) and metadata shared with the pre-existing document. The existence check targets the `DocumentStore`, so copying into a fresh `DocumentStore` that reuses an already-populated `MetadataStore` (`ContextWithMetadataStoreVersionsExist`) is still allowed.
- The split-store genesis rollback no longer joins a spurious `ErrDocumentNotFound` onto the real failure cause when a `CreateDocument` fails before any metadata row is inserted (for example a blob-write error). The metadata rollback is skipped when nothing was inserted and the blob rollback ignores not-found, so `errors.Is(err, ErrDocumentNotFound)` (and the `os.ErrNotExist` / `sql.ErrNoRows` it matches) no longer reports a document that was never created.

### Removed
- `pgstore.NewReadOnlyMetadataStore` is removed. For an immutable Postgres `MetadataStore`, derive a context with `pgstore.ContextWithMetadataStoreVersionsExist` (versions-exist mode); for a fully read-only `Conn`, wrap one with `docdb.ReadonlyConn`.

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
- `localfsdb.RestoreDocument` writes the correct `VersionInfo` (predecessor and file diff) when restoring a version that precedes the document's existing versions; it previously diffed such a version against the latest on-disk version, corrupting its metadata.
- `localfsdb.AddDocumentVersion` runs its error-path cleanup while still holding the per-document lock, closing a window where a concurrent writer could chain a new version off a half-written one.
- `storeconn.AddDocumentVersion` rolls back the metadata version when the file-content write fails, and `storeconn.RestoreDocument` rolls back partially-restored versions on error, so a failed operation no longer leaves a version referencing missing file content.
- `localfsdb.RestoreDocument` (recreate mode) surfaces a company-ID read error instead of swallowing it, so it no longer silently leaves a stale company-document marker behind.
- `HashedDocument.VersionInfo` returns nil for an internally inconsistent document instead of panicking.

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

[v0.8.1]: https://github.com/domonda/go-docdb/releases/tag/v0.8.1
[v0.8.0]: https://github.com/domonda/go-docdb/releases/tag/v0.8.0
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
