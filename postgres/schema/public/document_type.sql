create type public.document_type as enum (
    'INCOMING_INVOICE',
    'OUTGOING_INVOICE',
    'INCOMING_DUNNING_LETTER',
    'OUTGOING_DUNNING_LETTER',
    'INCOMING_DELIVERY_NOTE',
    'OUTGOING_DELIVERY_NOTE',
    'BANK_STATEMENT',
    'CREDITCARD_STATEMENT',
    'FACTORING_STATEMENT',
    'OTHER_DOCUMENT',
    'DMS_DOCUMENT',
    'DOCUMENT_EXPORT_FILE',    -- A document containing a file generated from a document(s) export
    'BANK_EXPORT_FILE',        -- A document containing a file generated from a bank export
    'ACL_IMPORT_FILE',         -- A document containing a file uploaded for ACL import
	'CREDITCARD_IMPORT_FILE',  -- A document containing a creditcard CSV import file
	'BANK_ACCOUNT_IMPORT_FILE' -- A document containing a bank account CSV import file
);

comment on type public.document_type is 'Document type';

----

create function public.document_type_has_pages(t public.document_type)
returns bool
language sql immutable strict as
$$
	select t in (
        'INCOMING_INVOICE',
        'OUTGOING_INVOICE',
        'INCOMING_DUNNING_LETTER',
        'OUTGOING_DUNNING_LETTER',
        'INCOMING_DELIVERY_NOTE',
        'OUTGOING_DELIVERY_NOTE',
        'BANK_STATEMENT',
        'CREDITCARD_STATEMENT',
        'FACTORING_STATEMENT',
        'OTHER_DOCUMENT'
    )
$$;

comment on function public.document_type_has_pages is 'Returns if the give document_type will have visual pages';

grant execute on function public.document_type_has_pages(public.document_type) to domonda_user;

----

create function public.document_type_has_extraction(t public.document_type)
returns bool
language sql immutable strict as
$$
	select t in (
        'INCOMING_INVOICE',
        'OUTGOING_INVOICE',
        'INCOMING_DELIVERY_NOTE',
        'OUTGOING_DELIVERY_NOTE'
    )
$$;

----

CREATE TABLE public.document_type_email_alias (
    type          public.document_type PRIMARY KEY,
    german_alias  public.email_alias NOT NULL UNIQUE,
    english_alias public.email_alias NOT NULL UNIQUE,

    created_at created_time NOT NULL
);

COMMENT ON TYPE public.document_type_email_alias IS 'Maps a document_type to its email aliases in different languages';

GRANT SELECT ON TABLE public.document_type_email_alias TO domonda_user;
