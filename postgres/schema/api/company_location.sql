create view api.company_location with (security_barrier) as
    select
        l.id,
        l.company_id,
        l.partner_company_id,
        l.created_by,
        l.main,
        l.street,
        l.city,
        l.zip,
        l.country,
        l.phone,
        l.email,
        l.website,
        l.registration_no,
        l.tax_id_no as tax_no,
        l.vat_id_no as vat_no,
        l.updated_at,
        l.created_at
    from public.company_location as l
    where
        -- Locations of all companies from public.company:
        l.partner_company_id is null
        -- Locations of all partners from the own company:
        or exists (
            select from public.partner_company as p
            where p.id = l.partner_company_id
                and p.client_company_id = api.current_client_company_id()
        );
grant select on table api.company_location to domonda_api;

comment on column api.company_location.created_by is '@notNull';
comment on column api.company_location.main is E'@notNull\nIndicates the main location of a company';
comment on column api.company_location.country is '@notNull';
comment on column api.company_location.registration_no is 'Country specific commercial register number (Firmenbuch/Handelsregister)';
comment on column api.company_location.updated_at is '@notNull';
comment on column api.company_location.created_at is '@notNull';
comment on view api.company_location is $$
@primaryKey id
@foreignKey (company_id) references api.company(id)
@foreignKey (partner_company_id) references api.partner_company(id)
Geographic location of a `Company` or subsidiary.
$$;


create function api.company_locations(company api.company)
returns setof api.company_location as
$$
    select *
    from api.company_location
    where company_id = company.id
    order by main desc, created_at
$$
language sql stable security definer;

comment on function api.company_locations is E'All locations of the `Company`.';


create function api.company_main_location(company api.company)
returns api.company_location as
$$
    select *
    from api.company_location
    where company_id = company.id and main = true
$$
language sql stable security definer;

comment on function api.company_main_location is E'Main location (headquarters) of the `Company`.';
