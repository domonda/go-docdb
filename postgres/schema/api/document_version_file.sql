CREATE VIEW api.document_version_file WITH (security_barrier) AS
    SELECT 
        document_version_id,
        name,
        size,
        hash
    FROM docdb.document_version_file AS dvf 
        INNER JOIN api.document_version AS dv ON (dv.id = dvf.document_version_id);

GRANT SELECT ON TABLE api.document_version_file TO domonda_api;

COMMENT ON COLUMN api.document_version_file.document_version_id IS '@notNull';
COMMENT ON COLUMN api.document_version_file.name IS '@notNull';
COMMENT ON COLUMN api.document_version_file.size IS '@notNull';
COMMENT ON COLUMN api.document_version_file.hash IS '@notNull';
COMMENT ON VIEW api.document_version_file IS '@foreignKey (document_version_id) references api.document_version (id)';
