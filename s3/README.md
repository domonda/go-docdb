# S3 Document Store for go-docdb

TODO: address the issues of the AI generated review below.

Not all points have to be fixed, for instance we assume that we can load all files into memory and don't nead a streaming implementation.

## AI generated review of the go-docdb/s3 package

### Overview
This package provides an S3-backed implementation of `docdb.DocumentStore` and a simple `FileProvider`. The implementation is concise and readable, but there are several correctness issues, brittle assumptions, and API ergonomics concerns that should be addressed for production robustness and scale.

### Strengths
- **Simple, readable code**: Small surface area with clear responsibilities (`DocumentStore`, `FileProvider`, and enumeration helper).
- **Deterministic key schema**: Keys are structured as `docID/filename/hash` which makes grouping and filtering intuitive.
- **Good unit tests coverage for happy paths**: Tests verify core flows (create, read, delete, enumeration) and some basic error cases.

### Bugs / Correctness Issues
- [x] **Response body not closed (connection leak)**
  - `ReadDocumentHashFile` does not `Close()` the `res.Body` after `io.ReadAll`.
  - `s3FileProvider.ReadFile` does not `Close()` the `resp.Body`.
  - Impact: HTTP connection leaks, increased memory/FD pressure, degraded performance under load.

- [x] **Brittle and potentially incorrect matching via substring contains**
  - `DocumentHashFileProvider` and `DeleteDocumentHashes` use `strings.Contains(*obj.Key, hash)` to match a hash.
  - Risks:
    - False positives if the hash substring appears in other path segments (docID or filename) or as a partial match.
    - Should instead split by `/` and compare the last segment (hash) for an exact match.

- :x: Hopefully no ducument will ever have 1000 objects **Pagination assumptions break with >1000 objects**
  - `DocumentHashFileProvider` uses a single `ListObjectsV2` call and assumes max 1000 files in a version.
  - `DeleteDocument` and `DeleteDocumentHashes` also assume a single page ("assuming there are max 1000 objects").
  - Impact: Objects beyond the first 1000 will be silently ignored, leading to incomplete reads/deletes.

- [x] filenames containing "/" now can't be saved **Key parsing and filename robustness**
  - `idFromKey` and `filenameFromKey` assume exactly 3 key segments.
  - If `filename` contains `/`, generated keys break the invariant and these parsers fail, causing errors or missing files.
  - Impact: Unexpected failures or skipped items when filenames contain slashes (which can happen for nested logical paths).

- [x] **Inconsistent prefixing**
  - Some listings use `Prefix: p(docID.String() + "/")` while others use `Prefix: p(docID.String())`.
  - Although functionally similar for current schema, using a trailing slash is safer to avoid matching docIDs that merely start with the same characters.

- [x] **`s3FileProvider.ReadFile` behavior when filename missing**
  - `findKey` returns `""` when not found, then `GetObject` is called with empty key. The resulting AWS error bubbles up rather than a domain error like `ErrNoSuchFile`.
  - Impact: Leaks backend-specific semantics to callers and makes error handling less predictable.

### Design / API Ergonomics Issues
- [x] **Context usage and configuration**
  - `NewS3DocumentStore` loads AWS config using `context.Background()` with no way to supply a custom `context.Context`, client, retry policy, endpoint (e.g., MinIO), or per-operation options.
  - Suggest providing constructors that accept an `*s3.Client`, or options (endpoint, region, retryer, timeouts, SSE/KMS, etc.).

- :x: unfortunately the content hash needs to be calculated, and that can only be done reading the whole file **Memory usage for large files**
  - `CreateDocument` reads each file fully into memory (`file.ReadAll()`), then uploads.
  - For large files this is inefficient and risks OOM. Prefer streaming uploads and, if needed, multipart uploads.

- :x: we don't need this / can be defined later **No content-type, metadata, SSE/KMS, ACL, or storage class configuration**
  - Uploads omit common S3 parameters (e.g., `ContentType`, `ServerSideEncryption`, `StorageClass`, tags).
  - Limits interoperability, compliance, and cost controls.

- :x: `EnumDocumentIDs` means enumerate over ALL documents. Probably this should go into the metadata store. **Enumeration over the entire bucket**
  - `EnumDocumentIDs` lists the whole bucket without a prefix and errors out when encountering keys not matching the 3-part schema.
  - In a shared bucket, unrelated keys can cause hard failures. Prefer scoping with a bucket prefix (e.g., a root path) or making the parser tolerant.

- [x] this was improved **Error propagation strategy**
  - Raw AWS errors are returned directly; there is no wrapping with context or normalization to domain-level errors.
  - Consider wrapping to add call context and to normalize expected cases (e.g., no-such-file) to stable sentinel errors.

- **Potential duplicates in `ListFiles`**
  - `ListFiles` collects filenames from the provided keys without deduplication.
  - Depending on input, duplicates may appear; could be surprising for callers.

### Testing Gaps
- :x: No test where it isn't needed. The pagination is being tested where it's being used. **No tests for >1000 objects** (pagination correctness for read and deletes).
- [x] this is fixed with validation **No tests for filenames containing `/`** and other characters that impact key structure.
- **No tests for hash substring collision** validating exact-segment match behavior.
- OMG **No tests verifying `Body.Close()` handling** to catch connection leaks.
- [x] **No negative tests for `FileProvider.ReadFile` unknown filename → domain error mapping.**

### Recommendations
- [x] **Fix resource leaks**
  - Always `defer res.Body.Close()` after successful `GetObject`. Consider using helpers to read-and-close safely.

- :x: **Implement robust pagination**
  - Replace single `ListObjectsV2` calls with paginated iteration in `DocumentHashFileProvider`, `DeleteDocument`, and `DeleteDocumentHashes`.

- [x] **Use exact segment comparisons**
  - When matching by hash, split key by `/` and compare the last segment for exact equality. Avoid `strings.Contains`.

- [x] **Harden key schema handling**
  - Validate and/or escape `/` in filenames before composing keys, or explicitly disallow `/` and enforce it at API boundaries.
  - Make parsers tolerant (e.g., allow `len(parts) >= 3` and pick the last two segments) if nested paths are desired.

- [x] **Improve API configurability**
  - Add a constructor that accepts an injected `*s3.Client` and/or functional options (endpoint/region/retryer/SSE/timeouts).
  - Accept a base `prefix` to scope all keys within a logical root path inside the bucket.

- :x: **Stream uploads and support multipart**
  - Avoid buffering entire files in memory. Use streaming uploads and multipart for large files.

- :x: **Enrich uploads with metadata and security**
  - Set `ContentType`, optionally `ContentDisposition`, `ServerSideEncryption` (SSE-S3 or KMS), `StorageClass`, and tags as needed.

- [x] **Normalize domain errors**
  - Map S3-specific 404/NoSuchKey to `ErrNoSuchFile` where appropriate (e.g., in `FileProvider.ReadFile`).

- :x: **Stabilize enumeration**
  - Use `Prefix` to constrain `EnumDocumentIDs` to this package’s keyspace. Tolerate or skip unknown shapes rather than failing hard.

- :x: **Round out tests**
  - Add cases for pagination (>1000 objects), filenames containing `/`, exact hash matching, and leak checks.

### Potential Refactor Sketches (high-level)
- :x: Introduce an options struct:
  - `type Options struct { Client *s3.Client; Bucket string; Prefix string; SSE *SSEConfig; StorageClass types.StorageClass; ... }`
  - `NewS3DocumentStoreWithOptions(ctx context.Context, opts Options) (*s3DocStore, error)`

- :x: Add helpers:
  - `readAllAndClose(body io.ReadCloser) ([]byte, error)` to enforce closing semantics.
  - `iterateAllObjects(ctx, client, bucket, prefix string, fn func(key string) error)` for pagination.

- :x: Harden key utilities:
  - `func Key(docID uu.ID, filename, hash string) (string, error)` returning error on invalid filename; or sanitize and document the behavior.

Addressing the above will significantly improve correctness, scalability, and maintainability, while keeping the package’s simplicity.


