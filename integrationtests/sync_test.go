package integrationtests

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/localfsdb"
	"github.com/domonda/go-docdb/storeconn"
	"github.com/domonda/go-docdb/storeconn/pgstore"
	"github.com/domonda/go-docdb/storeconn/pgstore/pgfixtures"
	"github.com/domonda/go-docdb/storeconn/s3store/s3fixtures"
	"github.com/domonda/go-types/uu"
)

// TestMain closes the process-wide Postgres test connection after all tests
// in the package have run, so no database connection is leaked.
func TestMain(m *testing.M) {
	code := m.Run()
	pgfixtures.CloseGlobalConn()
	os.Exit(code)
}

// syncBackend describes a docdb.Conn implementation that the sync tests
// exercise as both source and destination connection.
type syncBackend struct {
	name string
	// storeconn is true for the Postgres + S3 backed storeconn.Conn and
	// false for the local filesystem localfsdb.Conn. The flag is also used
	// to detect the storeconn->storeconn combination, where source and
	// destination share a single backend.
	storeconn bool
	// newConn builds a fresh Conn. Every backend registers its own cleanup
	// so nothing survives the test:
	//   - localfsdb.NewTestConn removes its temp directory on t.Cleanup.
	//   - the storeconn backend uses s3fixtures.FixtureCleanBucket, which
	//     deletes the bucket and all of its objects on t.Cleanup, and runs
	//     inside the rolled-back transaction of pgfixtures.FixtureCtxWithTestTx.
	newConn func(t *testing.T) docdb.Conn
}

func syncBackends() []syncBackend {
	return []syncBackend{
		{
			name: "localfsdb",
			newConn: func(t *testing.T) docdb.Conn {
				return localfsdb.NewTestConn(t)
			},
		},
		{
			name:      "storeconn",
			storeconn: true,
			newConn: func(t *testing.T) docdb.Conn {
				// FixtureCleanBucket provides an empty bucket and
				// registers a t.Cleanup that deletes the bucket together
				// with every object written during the test.
				s3fixtures.FixtureCleanBucket(t)
				return storeconn.New(
					s3fixtures.FixtureGlobalDocumentStore(t),
					pgstore.NewMetadataStore(),
				)
			},
		},
	}
}

// syncTestContext returns the context used by a sync test. When any backend is
// the storeconn backend the context must carry the Postgres test transaction
// so that every metadata write is rolled back on t.Cleanup. Tests that only
// use localfsdb need no database and get a plain context.
func syncTestContext(t *testing.T, backends ...syncBackend) context.Context {
	for _, b := range backends {
		if b.storeconn {
			return pgfixtures.FixtureCtxWithTestTx(t)
		}
	}
	return t.Context()
}

// createSyncTestDoc creates a document with two versions on conn: the first
// version adds a.txt, the second adds b.txt. The content argument keeps the
// file content distinct between documents so a mixed-up sync is detectable.
func createSyncTestDoc(t *testing.T, ctx context.Context, conn docdb.Conn, companyID, docID, userID uu.ID, content string) {
	t.Helper()
	noopOnNew := func(context.Context, *docdb.VersionInfo) error { return nil }

	err := conn.CreateDocument(
		ctx, companyID, docID, userID, "initial version",
		docdb.MustVersionTimeFromString("2024-01-01_00-00-00.000"),
		[]fs.FileReader{fs.NewMemFile("a.txt", []byte(content+"-a"))},
		noopOnNew,
	)
	require.NoError(t, err)

	err = conn.AddDocumentVersion(
		ctx, docID, userID, "second version",
		func(context.Context, uu.ID, docdb.VersionTime, docdb.FileProvider) (*docdb.CreateVersionResult, error) {
			return &docdb.CreateVersionResult{
				Version:    docdb.MustVersionTimeFromString("2024-01-01_00-00-00.001"),
				WriteFiles: []fs.FileReader{fs.NewMemFile("b.txt", []byte(content+"-b"))},
			}, nil
		},
		noopOnNew,
	)
	require.NoError(t, err)
}

// assertSyncedDocEqual reads the document want.ID from conn and asserts that
// it equals want version by version, including file content and metadata.
func assertSyncedDocEqual(t *testing.T, ctx context.Context, conn docdb.Conn, want *docdb.HashedDocument) {
	t.Helper()
	got, err := docdb.ReadHashedDocument(ctx, conn, want.ID)
	require.NoError(t, err)
	require.Equal(t, want.ID, got.ID)
	require.Equal(t, want.CompanyID, got.CompanyID)
	require.Equal(t, want.HashedFiles, got.HashedFiles)
	require.Equal(t, len(want.Versions), len(got.Versions))
	for v, wantVer := range want.Versions {
		gotVer, ok := got.Versions[v]
		require.Truef(t, ok, "version %s missing after sync", v)
		require.Equal(t, wantVer.CommitUserID, gotVer.CommitUserID)
		require.Equal(t, wantVer.CommitReason, gotVer.CommitReason)
		require.Equal(t, wantVer.FileHashes, gotVer.FileHashes)
	}
}

// countDocIDsInError reports how many of the passed docIDs are mentioned in
// the error. SyncDocument wraps every error with errs.WrapWithFuncParams,
// which embeds the docID, so a failure for a document always names it.
func countDocIDsInError(err error, docIDs uu.IDSlice) int {
	if err == nil {
		return 0
	}
	msg := err.Error()
	n := 0
	for _, docID := range docIDs {
		if strings.Contains(msg, docID.String()) {
			n++
		}
	}
	return n
}

// TestSyncDocument syncs a multi-version document for every combination of
// localfsdb and storeconn as source and destination connection.
func TestSyncDocument(t *testing.T) {
	for _, src := range syncBackends() {
		for _, dst := range syncBackends() {
			t.Run(src.name+" to "+dst.name, func(t *testing.T) {
				ctx := syncTestContext(t, src, dst)
				srcConn := src.newConn(t)
				dstConn := dst.newConn(t)

				companyID := uu.IDv7()
				docID := uu.IDv7()
				userID := uu.IDv7()

				createSyncTestDoc(t, ctx, srcConn, companyID, docID, userID, "doc")

				want, err := docdb.ReadHashedDocument(ctx, srcConn, docID)
				require.NoError(t, err)

				err = docdb.SyncDocument(ctx, srcConn, dstConn, docID, true)
				require.NoError(t, err)

				assertSyncedDocEqual(t, ctx, dstConn, want)
			})
		}
	}
}

// seedCompanyDocsWithConflicts creates goodCount + conflictCount documents for
// companyID on srcConn. For every conflicting document it also pre-creates the
// same docID on dstConn owned by a different company, so syncing it with
// recreate=false fails on the companyID mismatch while the good documents sync
// cleanly. It returns the good and conflicting docIDs separately.
func seedCompanyDocsWithConflicts(t *testing.T, ctx context.Context, srcConn, dstConn docdb.Conn, companyID uu.ID, goodCount, conflictCount int) (good, conflicting uu.IDSlice) {
	t.Helper()
	userID := uu.IDv7()
	for i := range goodCount {
		docID := uu.IDv7()
		createSyncTestDoc(t, ctx, srcConn, companyID, docID, userID, fmt.Sprintf("good%d", i))
		good = append(good, docID)
	}
	for i := range conflictCount {
		docID := uu.IDv7()
		createSyncTestDoc(t, ctx, srcConn, companyID, docID, userID, fmt.Sprintf("conflict%d", i))
		// Same docID on dst, but owned by a different company.
		// RestoreDocument with recreate=false rejects this mismatch.
		createSyncTestDoc(t, ctx, dstConn, uu.IDv7(), docID, userID, fmt.Sprintf("preexisting%d", i))
		conflicting = append(conflicting, docID)
	}
	return good, conflicting
}

func TestSyncAllCompanyDocuments(t *testing.T) {
	// Happy path: every document of the company is synced for all four
	// source/destination backend combinations.
	t.Run("syncs every document of the company", func(t *testing.T) {
		for _, src := range syncBackends() {
			for _, dst := range syncBackends() {
				t.Run(src.name+" to "+dst.name, func(t *testing.T) {
					ctx := syncTestContext(t, src, dst)
					srcConn := src.newConn(t)
					dstConn := dst.newConn(t)

					companyID := uu.IDv7()
					userID := uu.IDv7()

					companyDocIDs := uu.IDSlice{uu.IDv7(), uu.IDv7(), uu.IDv7()}
					for i, docID := range companyDocIDs {
						createSyncTestDoc(t, ctx, srcConn, companyID, docID, userID, fmt.Sprintf("doc%d", i))
					}

					// A document owned by a different company that
					// SyncAllCompanyDocuments must not touch.
					otherCompanyID := uu.IDv7()
					otherDocID := uu.IDv7()
					createSyncTestDoc(t, ctx, srcConn, otherCompanyID, otherDocID, userID, "other-company")

					// Record the progress callbacks to assert they report
					// every document with a correct index and total.
					type progress struct {
						docID        uu.ID
						index, total int
					}
					var progressCalls []progress
					synced, err := docdb.SyncAllCompanyDocuments(ctx, srcConn, dstConn, companyID, true, true,
						func(_ context.Context, docID uu.ID, index, total int) {
							progressCalls = append(progressCalls, progress{docID, index, total})
						},
					)
					require.NoError(t, err)
					require.ElementsMatch(t, companyDocIDs, synced)

					require.Len(t, progressCalls, len(companyDocIDs))
					var progressDocIDs uu.IDSlice
					for i, p := range progressCalls {
						require.Equal(t, i, p.index)
						require.Equal(t, len(companyDocIDs), p.total)
						progressDocIDs = append(progressDocIDs, p.docID)
					}
					require.ElementsMatch(t, companyDocIDs, progressDocIDs)

					for _, docID := range companyDocIDs {
						want, err := docdb.ReadHashedDocument(ctx, srcConn, docID)
						require.NoError(t, err)
						assertSyncedDocEqual(t, ctx, dstConn, want)
					}

					// When source and destination are distinct backends the
					// other company's document can only be in dst if it was
					// wrongly synced. storeconn->storeconn shares one backend,
					// so the document is present there regardless.
					if !(src.storeconn && dst.storeconn) {
						exists, err := dstConn.DocumentExists(ctx, otherDocID)
						require.NoError(t, err)
						require.False(t, exists, "document of another company must not be synced")
					}
				})
			}
		}
	})

	// continueOnError combinations exclude storeconn->storeconn: a single
	// shared backend cannot hold the same docID under two different
	// companies, which is how a per-document failure is provoked.
	continueOnErrorBackends := func(yield func(src, dst syncBackend) bool) {
		for _, src := range syncBackends() {
			for _, dst := range syncBackends() {
				if src.storeconn && dst.storeconn {
					continue
				}
				if !yield(src, dst) {
					return
				}
			}
		}
	}

	// continueOnError=true: a failing document does not stop the sync, the
	// other documents are still synced and the error is reported.
	t.Run("continueOnError=true syncs the documents that do not fail", func(t *testing.T) {
		for src, dst := range continueOnErrorBackends {
			t.Run(src.name+" to "+dst.name, func(t *testing.T) {
				ctx := syncTestContext(t, src, dst)
				srcConn := src.newConn(t)
				dstConn := dst.newConn(t)

				companyID := uu.IDv7()
				good, conflicting := seedCompanyDocsWithConflicts(t, ctx, srcConn, dstConn, companyID, 2, 1)

				synced, err := docdb.SyncAllCompanyDocuments(ctx, srcConn, dstConn, companyID, false, true, nil)
				require.Error(t, err)
				require.ElementsMatch(t, good, synced)
				require.NotContains(t, synced, conflicting[0])

				for _, docID := range good {
					want, err := docdb.ReadHashedDocument(ctx, srcConn, docID)
					require.NoError(t, err)
					assertSyncedDocEqual(t, ctx, dstConn, want)
				}
			})
		}
	})

	// continueOnError=true reports every failure: with all documents failing
	// the sync still visits each one, so the joined error names all of them.
	t.Run("continueOnError=true reports every failure", func(t *testing.T) {
		for src, dst := range continueOnErrorBackends {
			t.Run(src.name+" to "+dst.name, func(t *testing.T) {
				ctx := syncTestContext(t, src, dst)
				srcConn := src.newConn(t)
				dstConn := dst.newConn(t)

				companyID := uu.IDv7()
				_, conflicting := seedCompanyDocsWithConflicts(t, ctx, srcConn, dstConn, companyID, 0, 3)

				synced, err := docdb.SyncAllCompanyDocuments(ctx, srcConn, dstConn, companyID, false, true, nil)
				require.Error(t, err)
				require.Empty(t, synced)
				require.Equal(t, 3, countDocIDsInError(err, conflicting),
					"every failing document must be reported")
			})
		}
	})

	// continueOnError=false stops at the first failure: with all documents
	// failing the sync stops after the first, so exactly one is reported.
	t.Run("continueOnError=false stops at the first failure", func(t *testing.T) {
		for src, dst := range continueOnErrorBackends {
			t.Run(src.name+" to "+dst.name, func(t *testing.T) {
				ctx := syncTestContext(t, src, dst)
				srcConn := src.newConn(t)
				dstConn := dst.newConn(t)

				companyID := uu.IDv7()
				_, conflicting := seedCompanyDocsWithConflicts(t, ctx, srcConn, dstConn, companyID, 0, 3)

				synced, err := docdb.SyncAllCompanyDocuments(ctx, srcConn, dstConn, companyID, false, false, nil)
				require.Error(t, err)
				require.Empty(t, synced)
				require.Equal(t, 1, countDocIDsInError(err, conflicting),
					"sync must stop after the first failing document")
			})
		}
	})
}
