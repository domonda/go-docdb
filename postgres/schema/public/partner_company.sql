create table public.partner_company (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    company_id        uuid references public.company(id),
    constraint client_company_company_uniqueness unique(client_company_id, company_id),
    constraint client_is_own_partner check(client_company_id <> company_id),

    name text check(length(trim(name)) > 0), -- TODO change to check(length(name) > 0 and length(name) = length(trim(name))),
    constraint linked_company_or_name_check check(
        (name is null and company_id is not null) -- either references a company
        or
        (company_id is null and name is not null) -- or provides an internal name
    ),
    constraint company_name_uniqueness unique(client_company_id, name),

    derived_name trimmed_text, -- auto-generated (cannot use generated columns because of references to public.company)

    user_id       uuid references public.user(id) on delete set null,
    user_group_id uuid references public.user_group(id) on delete set null,

    constraint only_one_controller_type_allowed check(
      (user_id is null or user_group_id is null)
    ),

    -- used to map same companies which are named differently by an external source
    alternative_names text[] not null default '{}',
    constraint alternative_names_not_null_elements check(array_position(alternative_names, null) is null),

    -- source of partner insert, if applicable
    source text not null default 'UNKNOWN',

    paid_with_direct_debit boolean not null default false,

    notes non_empty_text,

    -- IMPORTANT: these two columns are added in invoice_partner_company_cost_centers_and_units.sql
    -- main_client_company_cost_center_id uuid references public.client_company_cost_center(id) on delete set null,
    -- main_client_company_cost_unit_id   uuid references public.client_company_cost_unit(id) on delete set null,

    updated_at  updated_time not null,
    created_at  created_time not null,

    disabled_by trimmed_text,
    disabled_at timestamptz,
    constraint disabled_by_at check((disabled_by is null) = (disabled_at is null))
);

create index partner_company_company_id_idx on public.partner_company (company_id);
create index partner_company_client_company_id_idx on public.partner_company (client_company_id);
create index partner_company_name_idx on public.partner_company (name);
create index partner_company_name_trgm_idx on public.partner_company using gist (name gist_trgm_ops);
create index partner_company_paid_with_direct_debit_idx on public.partner_company (paid_with_direct_debit);
create index partner_company_disabled_at_idx on public.partner_company (disabled_at);
create index partner_company_disabled_at_is_null_idx on public.partner_company ((disabled_at is null));

create index partner_company_derived_name_idx on public.partner_company (derived_name);
create index partner_company_derived_name_lower_idx on public.partner_company ((lower(derived_name)));
create index partner_company_derived_name_trgm_idx on public.partner_company using gist (derived_name gist_trgm_ops);
comment on column public.partner_company.derived_name is E'@notNull\nDerives the correct name of the `PartnerCompany`. It does so by always using the `internalName` field if present, falling back to the linked `Company.brandNameOrName`.';

-- IMPORTANT: these two indexes are added in invoice_partner_company_cost_centers_and_units.sql
-- create index partner_company_main_client_company_cost_center_id_idx on public.partner_company (main_client_company_cost_center_id);
-- create index partner_company_main_client_company_cost_unit_id_idx on public.partner_company (main_client_company_cost_unit_id);

grant select, insert, update, delete on table public.partner_company to domonda_user;
grant select on table public.partner_company to domonda_wg_user; -- TODO: just select I guess?

create function private.partner_company_set_derived_name()
returns trigger as $$
begin
    select trim(coalesce(
        new.name,
        (select public.company_brand_name_or_name(company)
        from public.company
        where company.id = new.company_id)
    )) into new.derived_name;
    if new.derived_name is null then
        raise exception 'Partner company must have a name';
    end if;
    return new;
end
$$ language plpgsql volatile strict;
create trigger partner_company_set_derived_name_trigger
  before insert or update on public.partner_company
  for each row
  execute procedure private.partner_company_set_derived_name();
create function private.company_set_partner_company_derived_name()
returns trigger as $$
begin
    -- will trigger "partner_company_set_derived_name_trigger"
    update public.partner_company
    set updated_at=now()
    where company_id = new.id;

    return new;
end
$$ language plpgsql volatile strict;
create trigger company_set_partner_company_derived_name_trigger
  after insert or update on public.company
  for each row
  execute procedure private.company_set_partner_company_derived_name();

create function private.partner_company_all_names(
    partner_company public.partner_company
) returns text[] as $$
    select array_cat(array[partner_company.derived_name::text], array_remove(partner_company.alternative_names, null))
$$ language sql immutable strict;

----

create function public.partner_companies_by_ids(
    ids uuid[]
) returns setof public.partner_company as
$$
    select * from public.partner_company where (id = any(ids))
$$
language sql stable strict;

comment on function public.partner_companies_by_ids is 'Returns `PartnerCompanies` matching the provided identifiers.';

create function public.partner_company_active(
    partner_company public.partner_company
) returns boolean as $$
    select partner_company.disabled_at is null
$$ language sql immutable strict;
comment on function public.partner_company_active is '@notNull';

----

-- IMPORTANT: these functions columns are added in invoice_partner_company_cost_centers_and_units.sql
-- create function public.create_partner_company
-- create function public.update_partner_company

----

create function public.delete_partner_company(
    id uuid
) returns public.partner_company as
$$
    delete from public.partner_company
        where id = delete_partner_company.id
    returning *
$$
language sql volatile strict;

----

create function public.update_partner_company_user_or_user_group(
    id            uuid,
    user_id       uuid = null,
    user_group_id uuid = null
) returns public.partner_company as
$$
    update public.partner_company
        set
            user_id=update_partner_company_user_or_user_group.user_id,
            user_group_id=update_partner_company_user_or_user_group.user_group_id,
            updated_at=now()
        where id = update_partner_company_user_or_user_group.id
    returning *
$$
language sql volatile;

----

create function private.check_partner_company_name()
returns trigger as $$
begin
  if exists (
    select from public.company
    where company.id = new.client_company_id
    and (
        lower(company.name) = lower(new.derived_name)
        or lower(company.brand_name) = lower(new.derived_name)
        or exists (
            select from unnest(company.alternative_names) as alternative_name
            where lower(alternative_name) = lower(new.derived_name)
        )
    )
  ) then
    if private.current_user_language() = 'de' then
    raise exception 'Sie können keinen Geschäftspartner mit demselben Namen oder Alternativnamen Ihrer eigenen Firma erstellen. Ihre Firmendaten werden in den Einstellungen verwaltet.';
    end if;

    raise exception 'Partner company can''t have own company name/alternative name. Own company data is managed in the account settings.';
  end if;
  return new;
end;
$$ language plpgsql stable;

create trigger check_partner_company_name
  after insert or update on public.partner_company
  for each row
  when (new.derived_name is not null)
  execute procedure private.check_partner_company_name();
