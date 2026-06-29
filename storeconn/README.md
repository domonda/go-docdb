# storeconn - Split-Store `docdb.Conn`

`storeconn.New(DocumentStore, MetadataStore)` builds a `docdb.Conn` out of **two
independent stores** instead of one monolithic backend:

- a **`DocumentStore`** that holds raw file content, addressed by content hash, and
- a **`MetadataStore`** that holds version metadata (company, user, reason, the
  per-version file lists, version ordering).

```go
conn := storeconn.New(
    s3store.NewDocumentStore(bucketName, s3Client), // file blobs
    pgstore.NewMetadataStore(),                     // version metadata in Postgres
)
docdb.Configure(conn)
```

The returned value satisfies the full `docdb.Conn` interface (see the root
[README](../README.md)), so callers cannot tell it apart from the single-store
`localfsdb.Conn`. This document explains what `New` returns, how the two stores
divide the work, and — the interesting part — how the orchestration layer keeps
two separate backends consistent without distributed transactions.

## Why split the store?

`localfsdb` keeps content and metadata together on one filesystem, which is
simple but ties both to the same machine. The split-store design lets each half
use the backend it is best suited to:

- **File content** is large, immutable, and content-addressable → object storage
  (`s3store`), where identical bytes deduplicate to a single object and blobs are
  cheap to store and serve.
- **Version metadata** is small, relational, queried by company / version / order,
  and needs uniqueness and ordering guarantees → a relational database
  (`pgstore`), which enforces the one-genesis-per-document constraint, strict
  version ordering, and company indexing that object storage cannot.

The cost of splitting is that a logical operation ("create a version") now spans
two systems that have no shared transaction. The `conn` type in
[storeconn.go](storeconn.go) is the layer that pays that cost: it sequences the
two stores and rolls back across them on failure.

## What `New` returns

`New` wraps the two stores in an unexported `conn` struct and returns it as a
`docdb.Conn`:

```go
func New(documentStore DocumentStore, metadataStore MetadataStore) docdb.Conn {
    return &conn{documentStore: documentStore, metadataStore: metadataStore}
}

type conn struct {
    documentStore DocumentStore
    metadataStore MetadataStore
}

var _ docdb.Conn = (*conn)(nil)
```

`conn` holds no state of its own beyond the two stores — no caches, no locks, no
connections. All state lives in the backends. Every `docdb.Conn` method is one of
two kinds:

1. **Pass-through** — forwarded verbatim to whichever single store owns that
   concern.
2. **Orchestrated** — split into ordered calls against *both* stores, with
   rollback wiring.

## Division of labor

The two interfaces are defined in [documentstore.go](documentstore.go) and
[metadatastore.go](metadatastore.go).

| Concern                                   | Owner           |
| ----------------------------------------- | --------------- |
| Raw file bytes, keyed by content hash     | `DocumentStore` |
| Deduplication of identical content        | `DocumentStore` |
| Existence of a document (any blobs?)      | `DocumentStore` |
| Enumerate all document IDs                | `DocumentStore` |
| Company ownership + the company index     | `MetadataStore` |
| Version timestamps and their ordering     | `MetadataStore` |
| Per-version file list + added/mod/removed | `MetadataStore` |
| `CommitUserID`, `CommitReason`            | `MetadataStore` |
| One-genesis-per-document uniqueness       | `MetadataStore` |

The pass-through methods map directly onto this table:

```go
func (c *conn) DocumentExists(ctx, docID)        { return c.documentStore.DocumentExists(...) }
func (c *conn) EnumDocumentIDs(ctx, cb)          { return c.documentStore.EnumDocumentIDs(...) }

func (c *conn) DocumentCompanyID(ctx, docID)     { return c.metadataStore.DocumentCompanyID(...) }
func (c *conn) DocumentVersions(ctx, docID)      { return c.metadataStore.DocumentVersions(...) }
func (c *conn) LatestDocumentVersionInfo(ctx, …) { return c.metadataStore.LatestDocumentVersionInfo(...) }
// …etc
```

## How the two halves map together

The link between metadata and content is the **content hash**. The
`MetadataStore` records, per version, a `map[filename]FileInfo` where each
`FileInfo` carries the file's content hash. The `DocumentStore` stores the bytes
under that same hash. Neither store references the other directly — the hash is
the only join key.

```
MetadataStore (Postgres)                 DocumentStore (S3)
─────────────────────────                ──────────────────────────────
version 2024-11-15_09:00                 object  <docID>/invoice.pdf/<hashA>
  invoice.pdf → FileInfo{hash: A} ──────▶ object  <docID>/data.json/<hashB>
  data.json   → FileInfo{hash: B} ──────▶
                                          (bytes deduplicated by hash:
version 2024-11-15_14:30                   an unchanged file across two
  invoice.pdf → FileInfo{hash: A} ──────▶  versions points at one object)
  data.json   → FileInfo{hash: C} ──────▶ object  <docID>/data.json/<hashC>
```

Two consequences fall out of this:

- **The metadata is authoritative for "what files a version has."** To read a
  version, `conn` first asks the `MetadataStore` for the version's `FileInfo`
  set, extracts the hashes, then asks the `DocumentStore` for exactly those
  hashes. The content store is never enumerated to *discover* a version's files.
- **Content is shared across versions.** Because an unchanged file keeps the same
  hash, successive versions point at the same blob. This is why deleting a version
  can never blindly delete its files' blobs — a sibling version may still
  reference them (see *Deletion* below).

### Reading a version (orchestrated read)

`DocumentVersionFileProvider` and `ReadDocumentVersionFile` both follow the
metadata-first pattern:

```go
func (c *conn) DocumentVersionFileProvider(ctx, docID, version) (FileProvider, error) {
    versionInfo, err := c.metadataStore.DocumentVersionInfo(ctx, docID, version) // 1. authoritative file set
    // …collect hashes from versionInfo.Files…
    return c.documentStore.DocumentHashFileProvider(ctx, docID, hashes)          // 2. resolve hashes to blobs
}
```

`ReadDocumentVersionFile` is the single-file variant: look up the filename in
`versionInfo.Files` to get its hash, then `ReadDocumentHashFile(docID, filename,
hash)`. A filename absent from the metadata returns `ErrDocumentFileNotFound`
before the content store is touched.

## Writing: two stores, no shared transaction

There is no cross-store transaction, so `conn` enforces a strict **order plus
compensating rollback**. The ordering and the rollback are the whole reason this
design is correct; each write method below is built around them.

### `CreateDocument` (genesis version)

[storeconn.go](storeconn.go) `CreateDocument`:

1. **Validate** version, non-empty file set, non-nil callback.
2. **Existence guard:** `documentStore.DocumentExists(docID)`. If blobs already
   exist, return `ErrDocumentAlreadyExists` *before* registering any rollback.
   This guard is what later licenses the rollback to delete blobs — it proved the
   store held nothing for this `docID` beforehand. (The guard checks the
   *documentStore*, not the metadataStore, so copying into a fresh content store
   that reuses a populated metadata store is still allowed — see
   *versions-exist mode*.)
3. **Write blobs:** `documentStore.CreateDocumentVersion` returns a `FileInfo`
   (name, size, hash) per file. These are reused directly so the files are not
   re-read or re-hashed.
4. **Write metadata:** `metadataStore.CreateDocumentVersion` with
   `PreviousVersion == nil` (genesis) and every file recorded as added.
5. **Commit callback:** `onNewVersion(versionInfo)`. If it errors or panics, the
   whole create is rolled back.

The deferred rollback is deliberately asymmetric about the *already-exists* case:

- **Blobs:** delete the whole document's blobs (a partial blob write may have
  stored objects but returned no `FileInfo`s) — *except* when the metadata insert
  failed with `ErrDocumentAlreadyExists`. That error means a concurrent writer won
  the one-genesis-per-document race and the content-addressed objects now under
  `docID` are *identical bytes shared with that winner*; deleting them would
  corrupt the winner, so they are left in place.
- **Metadata:** delete only the single genesis version this call inserted, and
  only if `versionInfo != nil` (it was actually inserted). `DeleteDocument` would
  wipe unrelated pre-existing versions; deleting `version` after a failed insert
  would wipe a colliding pre-existing version. A not-found result is ignored so a
  spurious not-found is never joined onto the real cause.

### `AddDocumentVersion` (append to existing document)

[storeconn.go](storeconn.go) `AddDocumentVersion`:

1. **Validate** IDs and callbacks; fetch `LatestDocumentVersionInfo` from
   metadata.
2. Build a `FileProvider` over the previous version's hashes so the user callback
   can read the prior files.
3. **Run `createVersion`** (wrapped to recover panics) to get the new version's
   `WriteFiles` / `RemoveFiles` / optional new company ID. Enforce the returned
   version is strictly *after* the latest.
4. Classify each written file as **added** vs **modified** by checking the prior
   provider, and compute the **resulting full file set** (previous − removed +
   added/modified). Reject removing *all* files — every version must keep at least
   one. This full set is passed to the metadata store as `Files` so it does not
   re-derive the carry-forward set.
5. **Write metadata first**, then **write blobs**. (Note the order is the
   opposite of `CreateDocument`: here the document already exists, so the metadata
   row is the thing that defines the new version, and it is written first.)
6. **Commit callback.** If the blob write or the callback fails,
   `rollbackNewVersion` runs.

`rollbackNewVersion` is the subtle part. It does **not** delete the new version's
added/modified hashes directly — those may be shared with sibling versions.
Instead it calls `metadataStore.DeleteDocumentVersion`, which returns the precise
set of hashes referenced *only* by the version being removed, and deletes exactly
those blobs. If the metadata delete itself fails, the safe hash set is unknown, so
the blobs are intentionally left rather than risk deleting shared content.

### `RestoreDocument` (rebuild from a `HashedDocument` backup)

[storeconn.go](storeconn.go) `RestoreDocument` replays each version of an
in-memory backup. It supports two modes:

- **`recreate=true`** — delete any existing document first, then rebuild. This is
  **not atomic** with respect to the pre-existing document: the delete happens up
  front and the rollback only undoes what this call created, so a mid-restore
  failure leaves the document absent until retried. Safe for the `SyncDocument`
  flow where the source still holds the data.
- **`recreate=false`** — additive merge: create if missing; otherwise keep
  existing versions and add only backup versions whose timestamp is not already on
  disk. CompanyID mismatch aborts without changes.

For middle versions it calls `metadataStore.CreateDocumentVersion` **directly**
(not `conn.AddDocumentVersion`) so the strictly-after ordering check is bypassed —
restoring versions out of "latest" order is expected. It diffs each version
against the *backup's* predecessor (not the DB's latest) to compute
added/modified/removed, and passes the version's authoritative full file set as
`Files`. A rollback removes versions created during the call (newest first), or
drops the whole document if it was created fresh here.

### Deletion

```go
func (c *conn) DeleteDocument(ctx, docID) {
    c.metadataStore.DeleteDocument(...)   // metadata first
    c.documentStore.DeleteDocument(...)   // then all blobs under the docID prefix
}

func (c *conn) DeleteDocumentVersion(ctx, docID, version) {
    leftVersions, hashesToDelete, _ := c.metadataStore.DeleteDocumentVersion(...) // returns the safe-to-delete hashes
    c.documentStore.DeleteDocumentHashes(ctx, docID, hashesToDelete)              // delete only those
}
```

The metadata store is the authority on which hashes are safe to delete:
`DeleteDocumentVersion` removes the version row and returns the hashes that no
remaining version references. Only those blobs are deleted, so shared content
survives.

## Ordering & rollback summary

The recurring rule across every orchestrated write:

- **Pick an order** — for genesis, blobs-then-metadata (metadata uniqueness is the
  commit point); for append, metadata-then-blobs (the metadata row defines the
  version).
- **Guard before you can clean up** — `CreateDocument`'s existence check is what
  makes deleting blobs on rollback safe.
- **Roll back by hash safety, not by name** — never delete a blob whose
  content hash might be shared; always ask the metadata store which hashes are
  exclusively the removed version's.
- **Never let cleanup mask the cause** — rollback errors are `errors.Join`ed onto
  the original error, and expected not-found results are ignored.

Because content is deduplicated by hash, the dangerous mistake everywhere is
deleting a blob another version still points at; the rollback code is shaped
entirely around avoiding it.

## `versions-exist` copy mode (`pgstore`)

`pgstore.ContextWithMetadataStoreVersionsExist(ctx)` switches the metadata store
into an **immutable, check-only** mode for copying a document's blobs into a *new*
`DocumentStore` while *reusing* the shared Postgres metadata:

- `CreateDocumentVersion` inserts nothing; it verifies the already-stored version
  matches what it would have inserted (error if missing or any field differs).
- `DeleteDocument` / `DeleteDocumentVersion` delete nothing; they verify existence
  and still report the `leftVersions` / hashes a real delete would, so the
  `conn` rollback can clean up the *content* store.

This is exactly why `CreateDocument`'s existence guard targets the
`documentStore` and not the `metadataStore`: with a fresh content store and a
populated metadata store, the document "exists" in metadata but not in blobs, and
the copy must be allowed to proceed.

## Concurrency

`conn` itself is stateless and adds no locking — concurrency safety is delegated
to the backends. The `MetadataStore`'s one-genesis-per-document unique constraint
is the serialization point for concurrent `CreateDocument` calls on the same
`docID`: the loser receives `ErrDocumentAlreadyExists`, and (as described above)
its rollback deliberately leaves the shared, content-addressed blobs in place
rather than corrupting the winner's document.

## Read-only wrapping

Wrap the result of `New` with `docdb.ReadonlyConn` to get a connection whose write
methods return `docdb.ErrReadonly` without touching either store; reads pass
through. See the root [README](../README.md#read-only-connections).
