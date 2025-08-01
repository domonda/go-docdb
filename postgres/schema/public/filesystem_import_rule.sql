CREATE TYPE public.import_fs_type AS ENUM (
    'LOCAL_FILESYSTEM',
    'DROPBOX_APP',
    'FTP'
);

COMMENT ON TYPE public.import_fs_type IS 'Filesystem type used to import documents';

----

CREATE TYPE public.import_period AS ENUM (
    'MONTH',
    'QUARTER'
);

COMMENT ON TYPE public.import_period IS 'Is the interval of the period used for import';

----

CREATE TABLE public.filesystem_import_rule (
    company_id uuid NOT NULL REFERENCES public.client_company(company_id) ON DELETE CASCADE, -- TODO rename to client_company_id
    name       text NOT NULL CHECK(length(name) > 0),
    PRIMARY KEY(company_id, name),

    fs_type   public.import_fs_type NOT NULL,
    base_path text NOT NULL,

    year_regex                 text NOT NULL CHECK(length(year_regex) > 0)             DEFAULT '^/(\d{4})/\d{2}(?:[_ \-][^/]+)?/[^/]+/[^/]+$',
    period_regex               text NOT NULL CHECK(length(period_regex) > 0)           DEFAULT '^/\d{4}/(\d{2})(?:[_ \-][^/]+)?/[^/]+/[^/]+$',
    period_interval            public.import_period NOT NULL                           DEFAULT 'MONTH',
    historic_regex             text                                                    DEFAULT '[Hh]istorisch/[^/]+$',
    incoming_invoice_regex     text NOT NULL CHECK(length(incoming_invoice_regex) > 0) DEFAULT '^/\d{4}/\d{2}(?:[_ \-][^/]+)?/(ER)/[^/]+$',
    outgoing_invoice_regex     text NOT NULL CHECK(length(outgoing_invoice_regex) > 0) DEFAULT '^/\d{4}/\d{2}(?:[_ \-][^/]+)?/(AR)/[^/]+$',
    bank_statement_regex       text                                                    DEFAULT '^/\d{4}/\d{2}(?:[_ \-][^/]+)?/(BK)/[^/]+$',
    creditcard_statement_regex text                                                    DEFAULT '^/\d{4}/\d{2}(?:[_ \-][^/]+)?/(KK)/[^/]+$',
    factoring_statement_regex  text                                                    DEFAULT '^/\d{4}/\d{2}(?:[_ \-][^/]+)?/(Factoring)/[^/]+$',
    other_document_regex       text                                                    DEFAULT '^/(\d{4}/)?(Sonstige Dokumente)|(Dokumente)/[^/]+$',
    include_regex              text,
    exclude_regex              text,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

COMMENT ON TABLE public.filesystem_import_rule IS 'Information or importing documents from a file system';

GRANT SELECT ON TABLE public.filesystem_import_rule TO domonda_user;

----

CREATE FUNCTION public.filesystem_import_rules_by_company_id(
    company_id uuid
) RETURNS SETOF public.filesystem_import_rule AS
$$
    SELECT * FROM public.filesystem_import_rule
        WHERE company_id = filesystem_import_rules_by_company_id.company_id
        ORDER BY created_at
$$
LANGUAGE SQL STABLE;

GRANT EXECUTE ON FUNCTION public.filesystem_import_rules_by_company_id(uuid) TO domonda_user;

----

CREATE FUNCTION public.add_filesystem_import_rule(
    company_id uuid,
    name       text,
    fs_type    public.import_fs_type,
    base_path  text
) RETURNS public.filesystem_import_rule AS
$$
    INSERT INTO
        public.filesystem_import_rule (
            company_id,
            name,
            fs_type,
            base_path
        )
        VALUES (
            add_filesystem_import_rule.company_id,
            add_filesystem_import_rule.name,
            add_filesystem_import_rule.fs_type,
            add_filesystem_import_rule.base_path
        )
        RETURNING *
$$
LANGUAGE SQL VOLATILE;

GRANT EXECUTE ON FUNCTION public.add_filesystem_import_rule(uuid, text, public.import_fs_type, text) TO domonda_user;

----

CREATE FUNCTION public.update_filesystem_import_rule(
    company_id uuid,
    name       text,
    fs_type    public.import_fs_type,
    base_path  text,
    year_regex                 text,
    period_regex               text,
    period_interval            public.import_period,
    historic_regex             text,
    incoming_invoice_regex     text,
    outgoing_invoice_regex     text,
    bank_statement_regex       text,
    creditcard_statement_regex text,
    factoring_statement_regex  text,
    other_document_regex       text,
    include_regex              text,
    exclude_regex              text
) RETURNS public.filesystem_import_rule AS
$$
    UPDATE public.filesystem_import_rule
        SET
            fs_type = update_filesystem_import_rule.fs_type,
            base_path = update_filesystem_import_rule.base_path,
            year_regex = update_filesystem_import_rule.year_regex,
            period_regex = update_filesystem_import_rule.period_regex,
            period_interval = update_filesystem_import_rule.period_interval,
            historic_regex = update_filesystem_import_rule.historic_regex,
            incoming_invoice_regex = update_filesystem_import_rule.incoming_invoice_regex,
            outgoing_invoice_regex = update_filesystem_import_rule.outgoing_invoice_regex,
            bank_statement_regex = update_filesystem_import_rule.bank_statement_regex,
            creditcard_statement_regex = update_filesystem_import_rule.creditcard_statement_regex,
            factoring_statement_regex = update_filesystem_import_rule.factoring_statement_regex,
            other_document_regex = update_filesystem_import_rule.other_document_regex,
            include_regex = update_filesystem_import_rule.include_regex,
            exclude_regex = update_filesystem_import_rule.exclude_regex,
            updated_at=now()
        WHERE
            company_id = update_filesystem_import_rule.company_id AND
            name = update_filesystem_import_rule.name
        RETURNING *
$$
LANGUAGE SQL VOLATILE;

GRANT EXECUTE ON FUNCTION public.update_filesystem_import_rule(uuid, text, public.import_fs_type, text, text, text, public.import_period, text, text, text, text, text, text, text, text, text) TO domonda_user;

----

CREATE FUNCTION public.delete_filesystem_import_rule(
    company_id uuid,
    name       text
) RETURNS SETOF public.filesystem_import_rule AS
$$
    DELETE FROM public.filesystem_import_rule
        WHERE
            company_id = delete_filesystem_import_rule.company_id AND
            name = delete_filesystem_import_rule.name
        RETURNING *
$$
LANGUAGE SQL VOLATILE;

GRANT EXECUTE ON FUNCTION public.delete_filesystem_import_rule(uuid, text) TO domonda_user;
