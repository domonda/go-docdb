CREATE FUNCTION super.pkey_column_for_table(
    table_schema text,
    table_name   text
) RETURNS text AS
$$
    SELECT kcu.column_name::text FROM information_schema.key_column_usage AS kcu
        INNER JOIN information_schema.table_constraints AS tc ON ((tc.constraint_name = kcu.constraint_name) AND (tc.constraint_type = 'PRIMARY KEY'))
    WHERE (
        kcu.table_schema = pkey_column_for_table.table_schema
    ) AND (
        kcu.table_name = pkey_column_for_table.table_name
    )
$$
LANGUAGE SQL IMMUTABLE;

----

CREATE FUNCTION super.make_computed_column(
    on_schema     text,
    on_table      text,
    on_table_pk   text,
    from_schema   text,
    from_table    text,
    from_table_pk text,
    returnsSETOF  boolean,
    name          text,
    "comment"     text
) RETURNS void AS
$$
BEGIN
    EXECUTE format(
        $function$
            CREATE FUNCTION %1$s.%2$s_%7$s(%2$s %1$s.%2$s) RETURNS %8$s %4$s.%5$s AS
            $query$SELECT * FROM %4$s.%5$s WHERE (%6$s = %2$s_%7$s.%2$s.%3$s)$query$
            LANGUAGE SQL STABLE
        $function$,
        make_computed_column.on_schema,    -- %1$s
        make_computed_column.on_table,     -- %2$s
        make_computed_column.on_table_pk,  -- %3$s
        make_computed_column.from_schema,  -- %4$s
        make_computed_column.from_table,   -- %5$s
        make_computed_column.from_table_pk,-- %6$s
        make_computed_column.name,         -- %7$s
        (CASE WHEN make_computed_column.returnsSETOF
            THEN 'SETOF'
            ELSE ''
        END) -- %8$s
    );

    IF COALESCE(TRIM(make_computed_column."comment"), '') <> '' THEN
        EXECUTE format(
            $comment$
                COMMENT ON FUNCTION %1$s.%2$s_%3$s(%1$s.%2$s) IS %4$s
            $comment$,
            make_computed_column.on_schema,               -- %1$s
            make_computed_column.on_table,                -- %2$s
            make_computed_column.name,                    -- %3$s
            quote_literal(make_computed_column."comment") -- %4$s
        );
    END IF;
END;
$$
LANGUAGE plpgsql VOLATILE;

---- EXAMPLE: ----
-- SELECT super.make_computed_column(
--     'api', 'invoice', 'document_id',
--     'api', 'document', 'id', false,
--     'document_by_document_id',
--     'The Document referenced by the Invoice using the `documentId`.'
-- ) -> FUNCTION api.invoice_document_by_invoice_id(api.invoice) RETURNS api.document WITH COMMENT 'The Document referenced by the Invoice using the `documentId`.';
