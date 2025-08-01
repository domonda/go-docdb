create view api.partner_account with (security_barrier) as
    select 
        id,
        partner_company_id,
        "type",
        "number",
        description,
        source,
        updated_at,
        created_at
    from public.partner_account
    where client_company_id = (select api.current_client_company_id());

grant select on table api.partner_account to domonda_api;

comment on column api.partner_account.partner_company_id is '@notNull';
comment on column api.partner_account.type is '@notNull';
comment on column api.partner_account.number is '@notNull';
comment on column api.partner_account.source is '@notNull';
comment on column api.partner_account.updated_at is '@notNull';
comment on column api.partner_account.created_at is '@notNull';
comment on view api.partner_account is $$
@primaryKey id
@foreignKey (partner_company_id) references public.partner_company (id)$$;

----

create function api.partner_company_vendor_account_number(
    partner_company api.partner_company
) returns text as
$$
    select partner_account.number from api.partner_account
    where partner_account.partner_company_id = partner_company.id
    and partner_account.type = 'VENDOR'
$$
language sql stable;


create function api.partner_company_client_account_number(
    partner_company api.partner_company
) returns text as
$$
    select partner_account.number from api.partner_account
    where partner_account.partner_company_id = partner_company.id
    and partner_account.type = 'CLIENT'
$$
language sql stable;