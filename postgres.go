package docdb

import (
	"context"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/nullable"
	"github.com/domonda/go-types/uu"
)

// PostgresGetDocumentVersionIDOrNull returns the version ID for a document version,
// or uu.IDNull if the version does not exist.
func PostgresGetDocumentVersionIDOrNull(ctx context.Context, documentID uu.ID, version VersionTime) (id uu.NullableID, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, documentID, version)

	return db.QueryRowAsOr(ctx,
		uu.IDNull,
		/*sql*/ `
			select id
			from docdb.document_version
			where document_id = $1 and version = date_trunc('milliseconds', $2::timestamp)
		`,
		documentID,
		version.Time,
	)
}

// PostgresGetDocumentVersionIDs returns all version IDs for a document ordered by version timestamp.
func PostgresGetDocumentVersionIDs(ctx context.Context, documentID uu.ID) (ids uu.IDSlice, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, documentID)

	return db.QueryRowAs[uu.IDSlice](ctx,
		/*sql*/ `
			select array_agg(id order by version)
			from docdb.document_version
			where document_id = $1
		`,
		documentID,
	)
}

// ToRefactorVersionExists checks if a specific version exists for a document.
// TODO: rename this function.
func ToRefactorVersionExists(ctx context.Context, documentID uu.ID, version VersionTime) (exists bool, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, documentID, version)

	return db.QueryRowAs[bool](ctx,
		/*sql*/ `
			select exists (
				select from docdb.document_version
				where document_id = $1 and version = date_trunc('milliseconds', $2::timestamp)
			)
		`,
		documentID,
		version.Time,
	)
}

// PostgresGetLatestVersion returns the latest version timestamp from the public.document table.
func PostgresGetLatestVersion(ctx context.Context, documentID uu.ID) (version VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, documentID)

	return db.QueryRowAs[VersionTime](ctx,
		/*sql*/ `select version from public.document where id = $1`,
		documentID,
	)
}

// PostgresGetLatestDocumentVersionTimeAndID returns the latest version timestamp
// and its corresponding version ID by joining public.document with docdb.document_version.
func PostgresGetLatestDocumentVersionTimeAndID(ctx context.Context, documentID uu.ID) (version VersionTime, id uu.ID, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, documentID)

	return db.QueryRowAs2[VersionTime, uu.ID](ctx,
		/*sql*/ `
			select doc.version, ver.id
			from public.document as doc
			inner join docdb.document_version as ver
				on ver.document_id = doc.id and ver.version = doc.version
			where doc.id = $1
		`,
		documentID,
	)
}

// PostgresInsertDocumentVersionIfMissing inserts the document information if there is no existing one.
func PostgresInsertDocumentVersionIfMissing(ctx context.Context, versionInfo *VersionInfo) (versionID uu.ID, didExist bool, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, versionInfo)

	err = db.Transaction(ctx, func(ctx context.Context) error {
		versionID, err = db.QueryRowAs[uu.ID](ctx,
			/*sql*/ `
				select id
				from docdb.document_version
				where document_id = $1
					and date_trunc('milliseconds', version) = $2
			`,
			versionInfo.DocID,
			versionInfo.Version,
		)
		switch {
		case errs.ReplaceErrNotFound(err, nil) != nil:
			return err
		case err == nil:
			didExist = true
			return nil
		}

		versionID = uu.NewID(ctx)
		return PostgresInsertDocumentVersionWithFiles(ctx, versionID, versionInfo)
	})
	if err != nil {
		return uu.IDNil, false, err
	}

	return versionID, didExist, nil
}

// PostgresInsertDocumentVersionWithFiles inserts a document version and its files into the database.
func PostgresInsertDocumentVersionWithFiles(ctx context.Context, versionID uu.ID, versionInfo *VersionInfo) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, versionID, versionInfo)

	return db.Transaction(ctx, func(ctx context.Context) error {
		err = db.Exec(ctx,
			/*sql*/ `
				insert into
				docdb.document_version (
					id,
					document_id,
					version,
					prev_version,
					commit_user_id,
					commit_reason,
					added_files,
					removed_files,
					modified_files
				)
				values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
			`,
			versionID,                                       // id
			versionInfo.DocID,                               // document_id
			versionInfo.Version,                             // version
			versionInfo.PrevVersion,                         // prev_version
			versionInfo.CommitUserID,                        // commit_user_id
			versionInfo.CommitReason,                        // commit_reason
			nullable.StringArray(versionInfo.AddedFiles),    // added_files
			nullable.StringArray(versionInfo.RemovedFiles),  // removed_files
			nullable.StringArray(versionInfo.ModifiedFiles), // modified_files
		)
		if err != nil {
			return err
		}

		for _, fileInfo := range versionInfo.Files {
			err = db.Exec(ctx,
				/*sql*/ `
					insert into docdb.document_version_file (
						document_version_id,
						name,
						size,
						hash
					)
					values ($1, $2, $3, $4)
				`,
				versionID,     // document_version_id
				fileInfo.Name, // name
				fileInfo.Size, // size
				fileInfo.Hash, // hash
			)
			if err != nil {
				return err
			}
		}
		return nil
	})
}

// PostgresDeleteDocumentVersionByID deletes a document version by its primary key ID.
func PostgresDeleteDocumentVersionByID(ctx context.Context, versionID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, versionID)

	err = db.Exec(ctx,
		/*sql*/ `delete from docdb.document_version where id = $1`, versionID,
	)
	if err != nil {
		return err
	}

	log.InfoCtx(ctx, "Deleted document version").
		UUID("versionID", versionID).
		Log()
	return nil
}
