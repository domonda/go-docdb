CREATE VIEW api.document_version WITH (security_barrier) AS
    SELECT 
        dv.id,
        dv.document_id,
        dv.version,
        dv.prev_version,
        dv.commit_user_id,
        dv.commit_reason,
        dv.added_files,
        dv.removed_files,
        dv.modified_files
    FROM docdb.document_version AS dv
        INNER JOIN api.document AS d ON (d.id = dv.document_id);

GRANT SELECT ON TABLE api.document_version TO domonda_api;

COMMENT ON COLUMN api.document_version.document_id IS '@notNull';
COMMENT ON COLUMN api.document_version.version IS '@notNull';
COMMENT ON COLUMN api.document_version.commit_user_id IS '@notNull';
COMMENT ON COLUMN api.document_version.commit_reason IS '@notNull';
COMMENT ON VIEW api.document_version IS $$
@primaryKey id
@foreignKey (document_id) references api.document (id)
@foreignKey (commit_user_id) references api.user (id)
A `DocumentVersion` is a version of a given `Document`.$$;
