# localfsdb - Local Filesystem Document Database

`localfsdb` is a file-based implementation of the `docdb.Conn` interface that stores documents and their versions as a structured directory hierarchy on the local filesystem.

## Directory Structure

The `localfsdb.Conn` manages three main directories:

```
<root>/
├── documents/       # Document storage with versions
├── workspace/       # Checked-out documents for editing
└── companies/       # Company-to-document mappings
```

### Documents Directory

The documents directory uses a UUID-based hierarchical structure (via `uuiddir`) where each document is represented by a directory named after its UUID. Within each document directory, versions are stored as timestamped subdirectories.

```
documents/
└── {doc-uuid-path}/              # e.g., ab/cd/ef12/3456/...
    ├── company.id                # Plain text file containing company UUID
    ├── checkout-status.json      # JSON file tracking checkout status (if checked out)
    ├── {version-timestamp}/      # e.g., 2024-01-15T10:30:45.123456Z/
    │   ├── doc.json              # Document metadata
    │   ├── source.pdf            # Original source file(s)
    │   └── ...                   # Any additional version files
    ├── {version-timestamp}.json  # VersionInfo metadata for each version
    └── ...                       # Additional versions
```

#### Example: Document with Multiple Versions

Here's a concrete example showing a document that has been edited multiple times:

```
documents/
└── 12/34/56ab/cdef/0123/4567/89abcdef/         # Document: 12345678-90ab-cdef-0123-456789abcdef
    │
    ├── company.id                              # Contains: a1b2c3d4-e5f6-7890-abcd-ef1234567890
    │
    ├── 2024-11-15T09:00:00.123456789Z/         # Version 1 (initial upload)
    │   ├── doc.json
    │   ├── doc.pdf                             # Original invoice
    │   └── extractiondata.json
    │
    ├── 2024-11-15T09:00:00.123456789Z.json     # VersionInfo for version 1
    │                                           # { "AddedFiles": ["doc.json", "doc.pdf", "extractiondata.json"],
    │                                           #   "PrevVersion": null, ... }
    │
    ├── 2024-11-15T14:30:15.987654321Z/         # Version 2 (OCR data added)
    │   ├── doc.json                            # Updated with OCR results
    │   ├── doc.pdf                             # Unchanged from v1
    │   ├── extractiondata.json                       # Unchanged from v1
    │   └── ocr-data.json                       # New file
    │
    ├── 2024-11-15T14:30:15.987654321Z.json     # VersionInfo for version 2
    │                                           # { "AddedFiles": ["ocr-data.json"],
    │                                           #   "ModifiedFiles": ["doc.json"],
    │                                           #   "PrevVersion": "2024-11-15T09:00:00.123456789Z", ... }
    │
    ├── 2024-11-16T11:20:30.555666777Z/         # Version 3 (attachment removed)
    │   ├── doc.json                            # Updated
    │   ├── doc.pdf                             # Unchanged from v2
    │   └── ocr-data.json                       # Unchanged from v2
    │
    └── 2024-11-16T11:20:30.555666777Z.json     # VersionInfo for version 3
                                                # { "RemovedFiles": ["extractiondata.json"],
                                                #   "ModifiedFiles": ["doc.json"],
                                                #   "PrevVersion": "2024-11-15T14:30:15.987654321Z", ... }
```

**Version Timeline:**
- **V1** (2024-11-15 09:00): Initial document creation with 3 files
- **V2** (2024-11-15 14:30): OCR processing added `ocr-data.json`, modified `doc.json`
- **V3** (2024-11-16 11:20): Removed `extractiondata.json`, modified `doc.json`

Each version directory contains a complete snapshot of the document at that point in time. The corresponding `.json` file tracks what changed from the previous version.

#### Key Files

- **`company.id`**: Contains the UUID of the company that owns this document as plain text. This file is written when a document is created or when the company is changed via `SetDocumentCompanyID()`.

- **`checkout-status.json`**: Present only when the document is checked out. Contains:
  - `companyID`: Company UUID
  - `docID`: Document UUID
  - `version`: Version that was checked out (null for new documents)
  - `userID`: User who checked out the document
  - `reason`: Reason for checkout
  - `time`: Checkout timestamp
  - `checkOutDir`: Path to the workspace directory

- **`{version-timestamp}/`**: Directory containing all files for a specific document version. The directory name is a UTC timestamp in RFC3339Nano format (e.g., `2024-01-15T10:30:45.123456789Z`).

- **`{version-timestamp}.json`**: VersionInfo metadata file containing:
  - `CompanyID`: Company UUID
  - `DocID`: Document UUID
  - `Version`: Version timestamp
  - `PrevVersion`: Previous version timestamp
  - `CommitUserID`: User who committed this version
  - `CommitReason`: Reason for creating this version
  - `Files`: Map of filename to file info (size, hash)
  - `AddedFiles`: List of files added in this version
  - `RemovedFiles`: List of files removed in this version
  - `ModifiedFiles`: List of files modified in this version

  **Example VersionInfo JSON** (`2024-11-15T14:30:15.987654321Z.json`):
  ```json
  {
    "CompanyID": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "DocID": "12345678-90ab-cdef-0123-456789abcdef",
    "Version": "2024-11-15T14:30:15.987654321Z",
    "PrevVersion": "2024-11-15T09:00:00.123456789Z",
    "CommitUserID": "user9876-5432-1098-7654-321098765432",
    "CommitReason": "OCR processing completed",
    "Files": {
      "doc.json": {
        "Name": "doc.json",
        "Size": 2048,
        "Hash": "sha256:a3f5e8c9d1b2e4f6a7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0"
      },
      "doc.pdf": {
        "Name": "doc.pdf",
        "Size": 524288,
        "Hash": "sha256:b4a6f9d0e2c3f5a7b8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1"
      },
      "extractiondata.json": {
        "Name": "extractiondata.json",
        "Size": 512,
        "Hash": "sha256:c5b7a0e1f3d4a6b8c9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2"
      },
      "ocr-data.json": {
        "Name": "ocr-data.json",
        "Size": 4096,
        "Hash": "sha256:d6c8b1f2a4e5b7c9d0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3"
      }
    },
    "AddedFiles": [
      "ocr-data.json"
    ],
    "RemovedFiles": [],
    "ModifiedFiles": [
      "doc.json"
    ]
  }
  ```

  This example shows Version 2 from the timeline above, where:
  - `ocr-data.json` was newly added
  - `doc.json` was modified (hash differs from previous version)
  - `doc.pdf` and `extractiondata.json` remain unchanged (same hashes as previous version)

### Workspace Directory

The workspace directory contains checked-out documents that are currently being edited. Each document being edited has its own directory named by the document UUID.

```
workspace/
└── {doc-uuid}/          # Document UUID (not hierarchical)
    ├── doc.json         # Working copy of document metadata
    ├── source.pdf       # Working copy of files
    └── ...              # Other working files
```

When a document is checked out:
1. A directory is created in `workspace/{doc-uuid}/`
2. All files from the latest version are copied to this directory
3. A `checkout-status.json` file is created in the document's main directory

### Companies Directory

The companies directory maintains a mapping from company UUIDs to document UUIDs using marker directories. This provides a threadsafe, filesystem-level index for quick enumeration of all documents belonging to a company.

```
companies/
└── {company-uuid}/           # Company UUID (plain UUID, not hierarchical)
    └── {doc-uuid-path}/      # Document UUID (hierarchical via uuiddir)
        └── (empty)           # Empty marker directory
```

The existence of the directory `companies/{company-uuid}/{doc-uuid-path}/` indicates that document `{doc-uuid}` belongs to company `{company-uuid}`.

## Document Version Creation Flow

### Creating a New Document

When `CreateDocument()` is called:

1. **Create document directory**: `documents/{doc-uuid-path}/` is created
2. **Write company ID**: `documents/{doc-uuid-path}/company.id` is written with the company UUID
3. **Create company mapping**: `companies/{company-uuid}/{doc-uuid-path}/` marker directory is created
4. **Create version directory**: `documents/{doc-uuid-path}/{version-timestamp}/` is created
5. **Copy files**: All provided files are copied into the version directory
6. **Generate VersionInfo**: File hashes and metadata are computed
7. **Write VersionInfo**: `documents/{doc-uuid-path}/{version-timestamp}.json` is written
8. **Call callback**: Optional `OnNewVersionFunc` is invoked

The entire operation is protected by a per-document mutex (`docWriteMtx.Lock(docID)`). If any step fails, cleanup logic removes all created directories.

### Adding a Version to an Existing Document

When `AddDocumentVersion()` is called:

1. **Lock document**: Acquire per-document write mutex
2. **Get previous version**: Read the latest `VersionInfo` and locate the previous version directory
3. **Call createVersion callback**: User-provided function determines which files to write/delete
4. **Create new version directory**: `documents/{doc-uuid-path}/{new-version-timestamp}/` is created
5. **Copy unchanged files**: Files from previous version that aren't being modified or deleted are copied
6. **Write new files**: Files returned by the callback are copied into the new version directory
7. **Generate VersionInfo**: Compare with previous version to identify added/modified/removed files
8. **Check for changes**: If files are identical to previous version, return `docdb.ErrNoChanges`
9. **Write VersionInfo**: `documents/{doc-uuid-path}/{new-version-timestamp}.json` is written
10. **Update company if changed**: If company ID changed, update `company.id` and company mapping directories
11. **Call callback**: Optional `OnNewVersionFunc` is invoked

If an error occurs, the new version directory and info file are removed during cleanup.

### Check-Out/Check-In Workflow

#### Check Out
When `CheckOutDocument()` is called:

1. **Verify not checked out**: Check that no `checkout-status.json` exists
2. **Get latest version**: Locate the latest committed version directory
3. **Create workspace**: `workspace/{doc-uuid}/` is created
4. **Copy files**: All files from the latest version are recursively copied to workspace
5. **Write checkout status**: `documents/{doc-uuid-path}/checkout-status.json` is created

#### Check In
When `CheckInDocument()` is called:

1. **Verify checked out**: Read and validate `checkout-status.json`
2. **Create new version**: Generate a new version timestamp
3. **Copy workspace files**: All files from `workspace/{doc-uuid}/` are copied to the new version directory
4. **Generate VersionInfo**: Compare with previous version (if any) to track changes
5. **Write VersionInfo**: Save version metadata JSON
6. **Clean up**: Remove `workspace/{doc-uuid}/` and `checkout-status.json`

#### Cancel Check Out
When `CancelCheckOutDocument()` is called:

1. **Read checkout status**: Verify document is checked out
2. **Delete workspace**: Remove `workspace/{doc-uuid}/` directory
3. **Delete checkout status**: Remove `checkout-status.json`
4. **For new documents**: Also delete the entire document directory from `documents/` since no version was ever committed

## Concurrency & Safety

- **Per-document mutex**: All write operations acquire a per-document mutex via `docWriteMtx.Lock(docID)` to prevent concurrent modifications to the same document
- **Atomic directory operations**: Directory existence is used as an atomic marker (e.g., for company-document mappings)
- **Error cleanup**: Defer functions clean up partially created structures on error
- **Version ordering**: Timestamps ensure strict version ordering

## UUID Directory Structure

The implementation uses `github.com/ungerik/go-fs/uuiddir` for efficient UUID-based directory hierarchies:

- UUIDs are split into path segments to avoid excessive files in a single directory
- Example: UUID `abcdef12-3456-7890-abcd-ef1234567890` becomes path `ab/cd/ef12/3456/7890/abcd/ef1234567890/`
- Special functions (`uuiddir.Join`, `uuiddir.RemoveDir`, etc.) handle the hierarchical structure

