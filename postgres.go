package docdb

import (
	"context"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/nullable"
	"github.com/domonda/go-types/uu"
)

func PostgresGetDocumentVersionIDOrNull(ctx context.Context, documentID uu.ID, version VersionTime) (id uu.NullableID, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, documentID, version)

	err = db.QueryRow(ctx,
		`select id
			from docdb.document_version
			where document_id = $1 and version = date_trunc('milliseconds', $2::timestamp)`,
		documentID,
		version.Time,
	).Scan(&id)
	if err != nil {
		return uu.IDNull, db.ReplaceErrNoRows(err, nil)
	}
	return id, nil
}

func PostgresGetDocumentVersionIDs(ctx context.Context, documentID uu.ID) (ids uu.IDSlice, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, documentID)

	return db.QueryValue[uu.IDSlice](ctx,
		`select array_agg(id order by version)
			from docdb.document_version
			where document_id = $1`, documentID)
}

func ToRefactorVersionExists(ctx context.Context, documentID uu.ID, version VersionTime) (exists bool, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, documentID, version)

	err = db.QueryRow(ctx,
		`select exists (
			select from docdb.document_version
				where document_id = $1 and version = date_trunc('milliseconds', $2::timestamp)
		)`,
		documentID,
		version.Time,
	).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}

// func VersionIDExists(ctx context.Context, documentVersionID uu.ID) (exists bool, err error) {
// 	defer errs.WrapWithFuncParams(&err, ctx, documentVersionID)

// 	err = db.QueryRow(ctx,
// 		`select exists(select from docdb.document_version where id = $1)`,
// 		documentVersionID,
// 	).Scan(&exists)
// 	if err != nil {
// 		return false, err
// 	}
// 	return exists, nil
// }

func PostgresGetLatestVersion(ctx context.Context, documentID uu.ID) (version VersionTime, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, documentID)

	err = db.QueryRow(ctx,
		`select version from public.document where id = $1`,
		documentID,
	).Scan(&version)
	if err != nil {
		return VersionTime{}, err
	}
	return version, nil
}

func PostgresGetLatestDocumentVersionTimeAndID(ctx context.Context, documentID uu.ID) (version VersionTime, id uu.ID, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, documentID)

	err = db.QueryRow(ctx,
		`select doc.version, ver.id
			from public.document as doc
			inner join docdb.document_version as ver
				on ver.document_id = doc.id and ver.version = doc.version
			where doc.id = $1`,
		documentID,
	).Scan(&version, &id)
	if err != nil {
		return VersionTime{}, uu.IDNil, err
	}
	return version, id, nil
}

// // GetLatestVersionsWithIDs returns the latest version timestamps and IDs of the passed documentIDs
// func GetLatestVersionsWithIDs(ctx context.Context, documentIDs uu.IDSlice) (versions []VersionTime, ids uu.IDSlice, err error) {
// 	defer errs.WrapWithFuncParams(&err, ctx, documentIDs)

// 	versions = make([]VersionTime, 0, len(documentIDs))
// 	ids = make(uu.IDSlice, 0, len(documentIDs))

// 	err = db.QueryRows(ctx,
// 		`select doc.version, ver.id
// 			from unnest($1::uuid[]) as document_id
// 			inner join public.document as doc
// 				on doc.id = document_id::uuid
// 			inner join docdb.document_version as ver
// 				on ver.document_id = doc.id and ver.version = doc.version;`,
// 		documentIDs,
// 	).ForEachRow(func(row sqldb.RowScanner) error {
// 		var (
// 			version VersionTime
// 			id      uu.ID
// 		)
// 		err := row.Scan(&version, &id)
// 		versions = append(versions, version)
// 		ids = append(ids, id)
// 		return err
// 	})
// 	if err != nil {
// 		return nil, nil, err
// 	}
// 	return versions, ids, nil
// }

// PostgresInsertDocumentVersionIfMissing inserts the document information if there is no existing one
func PostgresInsertDocumentVersionIfMissing(ctx context.Context, versionInfo *VersionInfo) (versionID uu.ID, didExist bool, err error) {
	defer errs.WrapWithFuncParams(&err, ctx, versionInfo)

	err = db.Transaction(ctx, func(ctx context.Context) error {
		err = db.QueryRow(ctx,
			`select id
				from docdb.document_version
				where
					document_id = $1
					and
					date_trunc('milliseconds', version) = $2`,
			versionInfo.DocID,
			versionInfo.Version,
		).Scan(&versionID)
		switch {
		case errs.ReplaceErrNotFound(err, nil) != nil:
			return err
		case err == nil:
			didExist = true
			return nil
		}

		versionID = uu.IDv4()
		return PostgresInsertDocumentVersionWithFiles(ctx, versionID, versionInfo)
	})
	if err != nil {
		return uu.IDNil, false, err
	}

	return versionID, didExist, nil
}

func PostgresInsertDocumentVersionWithFiles(ctx context.Context, versionID uu.ID, versionInfo *VersionInfo) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, versionID, versionInfo)

	return db.Transaction(ctx, func(ctx context.Context) error {
		tx := db.Conn(ctx)

		err = tx.Exec(
			`insert into
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
				values ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
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
			err = tx.Exec(
				`insert into
					docdb.document_version_file (
						document_version_id,
						name,
						size,
						hash
					)
					values ($1, $2, $3, $4)`,
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

func PostgresDeleteDocumentVersionByID(ctx context.Context, versionID uu.ID) (err error) {
	defer errs.WrapWithFuncParams(&err, ctx, versionID)

	err = db.Exec(ctx, `delete from docdb.document_version where id = $1`, versionID)
	if err != nil {
		return err
	}

	log.InfoCtx(ctx, "Deleted document version").
		UUID("versionID", versionID).
		Log()
	return nil
}

// func DeleteVersionByTimestamp(ctx context.Context, documentID uu.ID, version VersionTime) (versionID uu.ID, err error) {
// 	defer errs.WrapWithFuncParams(&err, ctx, documentID, version)

// 	err = db.QueryRow(ctx,
// 		`delete from docdb.document_version
// 			where document_id = $1 and version = date_trunc('milliseconds', $2::timestamp)
// 			returning id`,
// 		documentID,
// 		version.Time,
// 	).Scan(&versionID)
// 	if err != nil {
// 		return uu.IDNil, err
// 	}

// 	log.Info("Deleted document version").
// 		Ctx(ctx).
// 		UUID("versionID", versionID).
// 		Log()
// 	return versionID, nil
// }
