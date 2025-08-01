create view api.document_category with (security_barrier) as
    select 
        dc.id,
        dc.client_company_id,
        dc.document_type,
        dc.booking_type,
        dc.booking_category,
        dc.description,
        dc.email_alias,
        dc.general_ledger_account_id,
        dc.internal_number_mode,
        dc.internal_number_min,
        dc.updated_at,
        dc.created_at
    from public.document_category as dc
        join api.client_company as cc on (cc.company_id = dc.client_company_id);

grant select on table api.document_category to domonda_api;

comment on column api.document_category.client_company_id is '@notNull';
comment on column api.document_category.document_type is '@notNull';
comment on column api.document_category.updated_at is '@notNull';
comment on column api.document_category.created_at is '@notNull';
comment on view api.document_category is $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
@foreignKey (general_ledger_account_id) references api.general_ledger_account (id)
A `DocumentCategory` is a category of a document.$$;
