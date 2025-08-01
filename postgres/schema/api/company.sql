CREATE VIEW api.company WITH (security_barrier) AS
    SELECT
        c.id,
        c.name,
        c.brand_name,
        c.legal_form,
        c.founded,
        c.dissolved,
        c.updated_at,
        c.created_at,
        c.alternative_names
    FROM public.company AS c
    WHERE (
        -- can see self
        c.id = (SELECT api.current_client_company_id())
    ) OR (
        -- can see accounting company
        c.id = (SELECT accounting_company_client_company_id FROM public.client_company WHERE company_id = api.current_client_company_id())
    ) OR (
        -- can see partners
        EXISTS (
            SELECT FROM public.partner_company
            WHERE (
                client_company_id = (SELECT api.current_client_company_id())
            ) AND (
                company_id = c.id
            )
        )
    );

GRANT SELECT ON TABLE api.company TO domonda_api;

COMMENT ON COLUMN api.company.name IS '@notNull';
COMMENT ON COLUMN api.company.legal_form IS '@notNull';
COMMENT ON VIEW api.company IS $$
@primaryKey id
A `Company` represents a partner company of the currently authenticated client company.
$$;

----

CREATE VIEW api.client_company WITH (security_barrier) AS
    SELECT
        company_id,
        accounting_company_client_company_id,
        import_members,
        email_alias,
        processing,
        vat_declaration,
        updated_at,
        created_at
    FROM public.client_company
    WHERE company_id = (SELECT api.current_client_company_id());

GRANT SELECT ON TABLE api.client_company TO domonda_api;

COMMENT ON COLUMN api.client_company.accounting_company_client_company_id IS '@notNull';
COMMENT ON COLUMN api.client_company.import_members IS '@notNull';
COMMENT ON COLUMN api.client_company.email_alias IS '@notNull';
COMMENT ON COLUMN api.client_company.processing IS '@notNull';
COMMENT ON COLUMN api.client_company.vat_declaration IS '@notNull';
COMMENT ON VIEW api.client_company IS $$
@primaryKey company_id
@foreignKey (company_id) references api.company(id)
@foreignKey (accounting_company_client_company_id) references api.accounting_company(client_company_id)
Represents a `Company` which is a domonda *client* company.
$$;

create function api.client_company_has_accounting(cc api.client_company)
returns boolean as
$$
    select accounting_system is not null
    from public.client_company
    where company_id = cc.company_id
$$
language sql stable security definer;

comment on function api.client_company_has_accounting is E'`ClientCompany` has accounting enabled.';

----

CREATE VIEW api.accounting_company WITH (security_barrier) AS
    SELECT
        ac.client_company_id,
        ac.is_tax_adviser,
        ac.updated_at,
        ac.created_at
    FROM public.accounting_company AS ac
        INNER JOIN api.client_company AS cc ON (cc.accounting_company_client_company_id = ac.client_company_id);

GRANT SELECT ON TABLE api.accounting_company TO domonda_api;

COMMENT ON COLUMN api.accounting_company.is_tax_adviser IS '@notNull';
COMMENT ON VIEW api.accounting_company IS $$
@primaryKey client_company_id
@foreignKey (client_company_id) references api.client_company (company_id)
Represents a `Company` which is a domonda *accounting* company.
$$;

----

create function api.current_client_company()
returns api.client_company as
$$
    select * from api.client_company where company_id = (select api.current_client_company_id())
$$
language sql stable;

comment on function api.current_client_company is 'Currently authenticated `ClientCompany`.';

----

create view api.partner_company with (security_barrier) as
    select
        id,
        company_id,
        name,
        alternative_names,
        source,
        paid_with_direct_debit,
        disabled_at,
        disabled_by,
        disabled_at is null as active,
        updated_at,
        created_at
    from public.partner_company
    where client_company_id = (select api.current_client_company_id());

comment on column api.partner_company.alternative_names is '@notNull';
comment on column api.partner_company.source is '@notNull';
comment on column api.partner_company.paid_with_direct_debit is '@notNull';
comment on column api.partner_company.active IS E'@notNull\nIs the `PartnerCompany` active or not? You may also check the `disabledAt` and `disabledBy` fields.';

comment on view api.partner_company is $$
@primaryKey id
@foreignKey (company_id) references api.company(id)$$;

grant select, update on table api.partner_company to domonda_api;

----

create function api.partner_company_derived_name(
    partner_company api.partner_company
) returns text as
$$
    select coalesce(
        partner_company.name,
        (select coalesce(brand_name, name) from api.company where (id = partner_company.company_id))
    )
$$
language sql stable;

comment on function api.partner_company_derived_name IS E'@notNull\nDerives the correct name of the `PartnerCompany`. It does so by always using the `name` field if present, falling back to the linked `Company.brandNameOrName`.';

----

create function api.filter_partner_companies(
    search_text text = null
) returns setof api.partner_company as
$$
    select
        id,
        company_id,
        name,
        alternative_names,
        source,
        paid_with_direct_debit,
        disabled_at,
        disabled_by,
        disabled_at is null as active,
        updated_at,
        created_at
    from public.filter_partner_companies(api.current_client_company_id(), search_text)
$$
language sql stable security definer;

comment on function api.filter_partner_companies is 'Filter `PartnerCompanies`.';
