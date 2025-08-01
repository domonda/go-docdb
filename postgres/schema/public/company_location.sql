create table public.company_location (
    id uuid primary key default uuid_generate_v4(),

    company_id         uuid references public.company(id) on delete cascade,
    partner_company_id uuid references public.partner_company(id) on delete cascade,
    constraint company_or_partner_company_check check((company_id is null) <> (partner_company_id is null)),

    -- TODO add column client_company_id not null together with partner_company_id
    -- to enable uniqueness constraints per client company partner
    -- client_company_id uuid references public.client_company(company_id) on delete cascade,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- system-user ID for unknown user
        references public.user(id) on delete set default,

    -- the main location to use for this company. a client of domonda MUST always have a main location
    main boolean not null default false,

    street  non_empty_text,
    city    non_empty_text,
    zip     non_empty_text,
    country country_code not null default 'AT',

    phone   non_empty_text,
    email   public.email_addr,
    website non_empty_text,

    registration_no non_empty_text, -- UNIQUE commercial register number (at: firmenbuch, de/ch: handelsregister), TODO: rename to comp_reg_no
    tax_id_no       non_empty_text, -- UNIQUE general tax identification number
    vat_id_no       public.vat_id,  -- UNIQUE value added tax identification number

    -- constraint vat_id_no_in_country_check check(case
    --     when upper(left(vat_id_no, 2)) = 'EU' then true -- is a MOSS VAT-ID (does not link to a specific country)
    --     else vat_id_no is null or upper(left(vat_id_no, 2)) = upper(country)
    -- end),

    updated_at updated_time not null,
    created_at created_time not null
);

grant all on table public.company_location to domonda_user;
grant select on public.company_location to domonda_wg_user;

create index company_location_company_id_idx         on public.company_location (company_id);
create index company_location_partner_company_id_idx on public.company_location (partner_company_id);
create index company_location_registration_no_idx    on public.company_location (registration_no);
create index company_location_vat_id_no_idx          on public.company_location (vat_id_no);
create index company_location_email_idx              on public.company_location (email);

-- comment on constraint vat_id_no_in_country_check on public.company_location is
-- '@error The VAT-ID number must match the selected country.';

-- main
create unique index company_location_unique_main_company
    on public.company_location (company_id)
    where (main and company_id is not null);
create unique index company_location_unique_main_partner_company
    on public.company_location (partner_company_id)
    where (main and partner_company_id is not null);

-- country TODO-db-201207 do we really want this constraint? check the related Asana ticket
-- create unique index company_location_unique_country_company on public.company_location (company_id, country) where (company_id is not null);
-- create unique index company_location_unique_country_partner_company on public.company_location (partner_company_id, country) where (partner_company_id is not null);
-- registration_no
create unique index company_location_unique_registration_no_company
    on public.company_location (registration_no)
    where (company_id is not null);
create unique index company_location_unique_registration_no_partner_company
    on public.company_location (partner_company_id, registration_no)
    where (partner_company_id is not null);
-- tax_id_no
create unique index company_location_unique_tax_id_no_company
    on public.company_location (tax_id_no)
    where (company_id is not null);
create unique index company_location_unique_tax_id_no_partner_company
    on public.company_location (partner_company_id, tax_id_no)
    where (partner_company_id is not null);
-- vat_id_no
create unique index company_location_unique_vat_id_no_company
    on public.company_location (vat_id_no)
    where (company_id is not null);
create unique index company_location_unique_vat_id_no_partner_company
    on public.company_location (partner_company_id, vat_id_no)
    where (partner_company_id is not null);

----

create function public.company_location_title(
    company_location public.company_location
) returns text as $$
    select coalesce(
        company_location.city || ', ' || company_location.zip || ', ' || company_location.country || ' (' || company_location.vat_id_no::text || ')',
        company_location.city || ', ' || company_location.country || ' (' || company_location.vat_id_no::text || ')',
        company_location.country || ' (' || company_location.vat_id_no::text || ')',
        company_location.country
    )
$$ language sql immutable strict;
comment on function public.company_location_title is
'@notNull';

create function public.company_location_long_title(
    company_location public.company_location
) returns text as $$
    select
        array_to_string(
            array_remove(
                array[
                    company_location.city,
                    company_location.zip,
                    company_location.country
                ],
                null
            ),
        ' ')
        || ', ' ||
        array_to_string(
            array_remove(
                array[
                    company_location.vat_id_no,
                    company_location.phone,
                    company_location.email
                ],
                null
            ),
        ', ')
$$ language sql immutable strict;
comment on function public.company_location_long_title is
'@notNull';

create function public.create_company_location(
    main               boolean,
    country            country_code,
    company_id         uuid = null,
    partner_company_id uuid = null,
    street             non_empty_text = null,
    city               non_empty_text = null,
    zip                non_empty_text = null,
    phone              non_empty_text = null,
    email              public.email_addr = null,
    website            non_empty_text = null,
    registration_no    non_empty_text = null,
    tax_id_no          non_empty_text = null,
    vat_id_no          public.vat_id = null
) returns public.company_location as $$
    insert into public.company_location(
        company_id,
        partner_company_id,
        created_by,
        main,
        street,
        city,
        zip,
        country,
        phone,
        email,
        website,
        registration_no,
        tax_id_no,
        vat_id_no
    ) values (
        create_company_location.company_id,
        create_company_location.partner_company_id,
        private.current_user_id(),
        create_company_location.main,
        create_company_location.street,
        create_company_location.city,
        create_company_location.zip,
        create_company_location.country,
        create_company_location.phone,
        create_company_location.email,
        create_company_location.website,
        create_company_location.registration_no,
        create_company_location.tax_id_no,
        create_company_location.vat_id_no
    )
    returning *
$$ language sql volatile;

create function public.update_company_location(
    id                 uuid,
    main               boolean,
    country            country_code,
    street             non_empty_text = null,
    city               non_empty_text = null,
    zip                non_empty_text = null,
    phone              non_empty_text = null,
    email              public.email_addr = null,
    website            non_empty_text = null,
    registration_no    non_empty_text = null,
    tax_id_no          non_empty_text = null,
    vat_id_no          public.vat_id = null
) returns public.company_location as $$
    update public.company_location set
        main=update_company_location.main,
        street=update_company_location.street,
        city=update_company_location.city,
        zip=update_company_location.zip,
        country=update_company_location.country,
        phone=update_company_location.phone,
        email=update_company_location.email,
        website=update_company_location.website,
        registration_no=update_company_location.registration_no,
        tax_id_no=update_company_location.tax_id_no,
        vat_id_no=update_company_location.vat_id_no,
        updated_at=now()
    where id = update_company_location.id
    returning *
$$ language sql volatile;

create function public.delete_company_location(
    id uuid
) returns public.company_location as $$
    delete from public.company_location
    where id = delete_company_location.id
    returning *
$$ language sql volatile strict;

----

create function public.company_locations(
    company public.company
) returns setof public.company_location as $$
    select * from public.company_location
    where company_id = company.id
    order by
        company_location.main desc, -- main company_location on top (`true` on top)
        company_location.created_at desc
$$ language sql stable strict;

create function public.company_non_main_locations(
    company public.company
) returns setof public.company_location as $$
    select * from public.company_location
    where company_id = company.id
    and not main
    order by company_location.created_at desc
$$ language sql stable strict;

create function public.company_main_location(
    company public.company
) returns public.company_location as $$
    select * from public.company_location
    where company_id = company.id
    and company_location.main
$$ language sql stable strict;

-- TODO-db-201111 can be very long, take first 3 and append `+N`
create function public.company_aggregated_vat_id_nos(
    company public.company
) returns text as $$
    select string_agg(vat_id_no, ', ') from public.company_locations(company) as company_location
    where company_location.company_id = company.id
$$ language sql stable strict;
comment on function public.company_aggregated_vat_id_nos is
'Aggregates VAT-ID numbers from the related locations and joins them to a comma (`,`) separated string.';

-- TODO-db-201111 can be very long, take first 3 and append `+N`
create function public.company_aggregated_countries(
    company public.company
) returns text as $$
    select string_agg(country, ', ') from public.company_locations(company) as company_location
    where company_location.company_id = company.id
$$ language sql stable strict;
comment on function public.company_aggregated_vat_id_nos is
'Aggregates countries from the related locations and joins them to a comma (`,`) separated string.';

create function public.company_name_with_vat_id_nos(
    company public.company
) returns text as
$$
    select coalesce(
        public.company_brand_name_or_name(company) || ' (' || public.company_aggregated_vat_id_nos(company) || ')',
        public.company_brand_name_or_name(company))
$$
language sql stable strict;
comment on function public.company_name_with_vat_id_nos is
E'@notNull\nUses the `brandName` or `name` from the `Company` and aggregates all location VAT-IDs in parentheses separated by comma (`,`). If no locations are available, only the name will be shown.';

----

create function public.partner_company_locations(
    partner_company public.partner_company
) returns setof public.company_location as $$
    select * from public.company_location
    where partner_company_id = partner_company.id
    or company_id = partner_company.company_id -- can be the location of the linked company
    order by
        company_location.partner_company_id nulls last, -- prefer focused company_locations
        company_location.main desc, -- main company_location on top (`true` on top)
        company_location.created_at desc
$$ language sql stable strict;

create function public.partner_company_non_main_locations(
    partner_company public.partner_company
) returns setof public.company_location as $$
    select * from public.company_location
    where (partner_company_id = partner_company.id
        or company_id = partner_company.company_id) -- can be the location of the linked company
    and not main
    order by
        company_location.partner_company_id nulls last, -- prefer focused company_locations
        company_location.created_at desc
$$ language sql stable strict;

create function public.partner_company_main_location(
    partner_company public.partner_company
) returns public.company_location as $$
    select * from public.company_location
    where (partner_company_id = partner_company.id
        or company_id = partner_company.company_id) -- can be the location of the linked company
    and company_location.main
    order by company_location.partner_company_id nulls last -- prefer focused company_locations
    limit 1
$$ language sql stable strict;

-- TODO-db-201111 can be very long, take first 3 and append `+N`
create function public.partner_company_aggregated_vat_id_nos(
    partner_company public.partner_company
) returns text as $$
    select string_agg(vat_id_no, ', ')
    from public.partner_company_locations(partner_company)
$$ language sql stable strict;
comment on function public.partner_company_aggregated_vat_id_nos is
'Aggregates VAT-ID numbers from the related locations and joins them to a comma (`,`) separated string.';

-- TODO-db-201111 can be very long, take first 3 and append `+N`
create function public.partner_company_aggregated_countries(
    partner_company public.partner_company
) returns text as $$
    select string_agg(country, ', ')
    from public.partner_company_locations(partner_company)
$$ language sql stable strict;
comment on function public.partner_company_aggregated_vat_id_nos is
'Aggregates countries from the related locations and joins them to a comma (`,`) separated string.';

create function public.partner_company_derived_name_with_vat_id_nos(
    partner_company public.partner_company
) returns text as
$$
    select coalesce(
        partner_company.derived_name || ' (' || public.partner_company_aggregated_vat_id_nos(partner_company) || ')',
        partner_company.derived_name)
$$
language sql stable strict;
comment on function public.partner_company_derived_name_with_vat_id_nos is
E'@notNull\nDerives the correct name of the `PartnerCompany` and aggregates all location VAT-IDs in parentheses separated by comma (`,`). If no locations are available, only the name will be shown.';

-- Triggers

create function check_company_location_at_least_one_main_for_company()
returns trigger as $$
begin
    if
        not new.main
        and new.company_id is not null
        and not exists (select from public.company_location where main and id <> new.id and company_id = new.company_id)
    then
        raise exception 'A company must have a main location!';
    end if;
	return new;
end;
$$ language plpgsql stable;

create trigger check_at_least_one_main_for_company
    before insert or update on public.company_location
    for each row
    execute procedure check_company_location_at_least_one_main_for_company();

----

create function private.check_partner_company_location_vat_id_no_and_email()
returns trigger as $$
begin
    if exists (
        select from public.company_location
            inner join public.partner_company on partner_company.id = new.partner_company_id
        where company_location.company_id = partner_company.client_company_id
        and (
            company_location.vat_id_no = new.vat_id_no
            or company_location.email = new.email
        )
    ) then
        if private.current_user_language() = 'de' then
            raise exception 'Sie können keinen Geschäftspartner mit derselben UID-Nummer oder E-Mail-Adresse Ihrer eigenen Firma erstellen. Ihre Firmendaten werden in den Einstellungen verwaltet.';
        end if;

        raise exception 'Partner company can''t have own company VAT-ID or email. Own company data is managed in the account settings.';
    end if;
	return new;
end;
$$ language plpgsql stable;

create trigger check_partner_company_location_vat_id_no_and_email
  before insert or update on public.company_location
  for each row
  when (new.partner_company_id is not null and (new.vat_id_no is not null or new.email is not null))
  execute procedure private.check_partner_company_location_vat_id_no_and_email();

--

create function public.partner_company_is_consumer(
    partner_company public.partner_company
) returns boolean as $$
    select not exists (
        select from public.company_location
        where (partner_company_id = partner_company.id
            or company_location.company_id = partner_company.company_id) -- can be the location of the linked company
        and vat_id_no is not null
    )
$$ language sql strict stable;
