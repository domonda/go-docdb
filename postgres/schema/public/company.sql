create table public.company (
    id         uuid primary key,

    -- TODO-db-201027 rename to `legal_name` and use `name` as a computed column instead of `brand_name_or_name`
    name text not null check (length(trim(name)) = length(name) and length(name) >= 2),
    -- TODO-db-201118 future cleanup
    -- constraint name_uniqueness unique(name),

    alternative_names text[], -- used to map same companies which are named differently from an external source
    brand_name        text check(length(trim(brand_name)) > 0),

    legal_form public.legal_form,

    founded   date,
    dissolved date,

    source text, -- source holds optional information if company got imported from a 3rd party source

    updated_at updated_time not null,
    created_at created_time not null
);

comment on table public.company is 'General company info';
comment on column public.company.name is 'The official name of company';
comment on column public.company.created_at is 'Creation time of object.';

create index company_name_idx on public.company (name);
create index company_name_trgm_idx on public.company using gist (name gist_trgm_ops);
create index company_name_lower_idx on public.company ((lower(name)));
create index company_brand_name_idx on public.company (brand_name);
create index company_brand_name_lower_idx on public.company ((lower(brand_name)));
create index company_brand_name_trgm_idx on public.company using gist (brand_name gist_trgm_ops);

grant select, insert, update, delete on table public.company to domonda_user;
grant select on table public.company to domonda_wg_user; -- TODO: just select I guess?

----

-- TODO-db-201027 rename `name` to `legal_name` use this computed column as `company_name`
create function public.company_brand_name_or_name(
    company public.company
) returns text as
$$
    select coalesce(company_brand_name_or_name.company.brand_name, company_brand_name_or_name.company.name)
$$
language sql immutable strict;

comment on function public.company_brand_name_or_name is e'@notNull\nReturns the representational name of the company.';

create index company_brand_name_or_name_idx on public.company (public.company_brand_name_or_name(company));
create index company_brand_name_or_name_trgm_idx on public.company using gist (public.company_brand_name_or_name(company) gist_trgm_ops);

----

create function public.company_has_name(
    comp   public.company,
    "name" text
) returns boolean as
$$
    select coalesce(
        (
            comp.name = "name"
            or (comp.brand_name        is not null and comp.brand_name = "name")
            or (comp.alternative_names is not null and "name" = any(comp.alternative_names))
        ),
        false
    )
$$
language sql immutable;

comment on function public.company_has_name is e'@notNull\nReturns if the company has the passed name as exact name, brand-name or alternative name';

----

create function public.create_company(
    "name"            text,
    alternative_names text[] = null,
    brand_name        text = null,
    legal_form        public.legal_form = null,
    founded           date = null,
    dissolved         date = null
) returns public.company as
$$
    insert into public.company (
        id,
        "name",
        alternative_names,
        brand_name,
        legal_form,
        founded,
        dissolved,
        source
    ) values (
        uuid_generate_v4(),
        create_company.name,
        create_company.alternative_names,
        create_company.brand_name,
        create_company.legal_form,
        create_company.founded,
        create_company.dissolved,
        'USER_CREATE'
    )
    returning *
$$
language sql volatile;

comment on function public.create_company is 'Create a new `Company`.';

----

create function public.update_company(
    company_id        uuid,
    "name"            text,
    alternative_names text[] = null,
    brand_name        text = null,
    legal_form        public.legal_form = null,
    founded           date = null,
    dissolved         date = null
) returns public.company as
$$
    update public.company
        set
            "name"=update_company.name,
            alternative_names=update_company.alternative_names,
            brand_name=update_company.brand_name,
            legal_form=update_company.legal_form,
            founded=update_company.founded,
            dissolved=update_company.dissolved,
            updated_at=now()
        where (id = update_company.company_id)
    returning *
$$
language sql volatile;

comment on function public.update_company is 'Updates the related `Company`.';

----

-- no delete mutation intentionally

----

create function public.companies_by_ids(
    ids uuid[]
) returns setof public.company as
$$
    select * from public.company where (id = any(ids))
$$
language sql stable strict;

comment on function public.companies_by_ids is 'Returns `Companies` matching the `ids`.';

----

-- Hard coded company IDs:

----

create function public.company_id_domonda() returns uuid
language sql immutable parallel safe as
$$
    select '7acda277-f07c-4975-bd12-d23deace6a9a'::uuid
$$;

comment on function public.company_id_domonda is 'Company ID of DOMONDA GmbH';

create function public.company_id_libraconsult() returns uuid
language sql immutable parallel safe as
$$
    select 'c1fd6da0-e1e5-4607-bc92-885339a37649'::uuid
$$;

comment on function public.company_id_libraconsult is 'Company ID of Libraconsult Steuerberatung GmbH';