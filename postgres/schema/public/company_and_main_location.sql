create function public.create_company_and_main_location(
  "name"            text,
  country           country_code,
  alternative_names text[] = null,
  brand_name        text = null,
  legal_form        public.legal_form = null,
  founded           date = null,
  dissolved         date = null,
  street            non_empty_text = null,
  city              non_empty_text = null,
  zip               non_empty_text = null,
  phone             non_empty_text = null,
  email             public.email_addr = null,
  website           non_empty_text = null,
  registration_no   non_empty_text = null,
  tax_id_no         non_empty_text = null,
  vat_id_no         public.vat_id = null
) returns public.company as $$
  with inserted_company as (
    insert into public.company (id, "name", alternative_names, brand_name, legal_form, founded, dissolved)
    values (
      uuid_generate_v4(),
      create_company_and_main_location.name,
      create_company_and_main_location.alternative_names,
      create_company_and_main_location.brand_name,
      create_company_and_main_location.legal_form,
      create_company_and_main_location.founded,
      create_company_and_main_location.dissolved)
    returning *
  ), inserted_location as (
    insert into public.company_location (company_id, main, street, city, zip, country, phone, email, website, registration_no, tax_id_no, vat_id_no)
    select
      inserted_company.id,
      true,
      create_company_and_main_location.street,
      create_company_and_main_location.city,
      create_company_and_main_location.zip,
      create_company_and_main_location.country,
      create_company_and_main_location.phone,
      create_company_and_main_location.email,
      create_company_and_main_location.website,
      create_company_and_main_location.registration_no,
      create_company_and_main_location.tax_id_no,
      create_company_and_main_location.vat_id_no
    from inserted_company
    returning 1)
  select inserted_company.* from inserted_company, inserted_location
$$ language sql volatile;

create function public.update_company_and_main_location(
  company_id        uuid,
  "name"            text,
  country           country_code,
  alternative_names text[] = null,
  brand_name        text = null,
  legal_form        public.legal_form = null,
  founded           date = null,
  dissolved         date = null,
  street            non_empty_text = null,
  city              non_empty_text = null,
  zip               non_empty_text = null,
  phone             non_empty_text = null,
  email             public.email_addr = null,
  website           non_empty_text = null,
  registration_no   non_empty_text = null,
  tax_id_no         non_empty_text = null,
  vat_id_no         public.vat_id = null
) returns public.company as $$
  with updated_company as (
    update public.company set
      "name"=update_company_and_main_location.name,
      alternative_names=update_company_and_main_location.alternative_names,
      brand_name=update_company_and_main_location.brand_name,
      legal_form=update_company_and_main_location.legal_form,
      founded=update_company_and_main_location.founded,
      dissolved=update_company_and_main_location.dissolved,
      updated_at=now()
    where id = update_company_and_main_location.company_id
    returning *
  ), upserted_location as (
    -- handle cases where a main location does not exist
    insert into public.company_location (company_id, main, street, city, zip, country, phone, email, website, registration_no, tax_id_no, vat_id_no)
    select
      updated_company.id,
      true,
      update_company_and_main_location.street,
      update_company_and_main_location.city,
      update_company_and_main_location.zip,
      update_company_and_main_location.country,
      update_company_and_main_location.phone,
      update_company_and_main_location.email,
      update_company_and_main_location.website,
      update_company_and_main_location.registration_no,
      update_company_and_main_location.tax_id_no,
      update_company_and_main_location.vat_id_no
    from updated_company
    -- unique index "company_location_unique_main_company"
    on conflict (company_id) where (main and company_id is not null) do update set
      street=update_company_and_main_location.street,
      city=update_company_and_main_location.city,
      zip=update_company_and_main_location.zip,
      country=update_company_and_main_location.country,
      phone=update_company_and_main_location.phone,
      email=update_company_and_main_location.email,
      website=update_company_and_main_location.website,
      registration_no=update_company_and_main_location.registration_no,
      tax_id_no=update_company_and_main_location.tax_id_no,
      vat_id_no=update_company_and_main_location.vat_id_no,
      updated_at=now()
    returning company_id)
  select updated_company.* from updated_company, upserted_location
$$ language sql volatile;

----

-- IMPORTANT: these functions columns are added in invoice_partner_company_cost_centers_and_units.sql
-- create function public.create_partner_company_and_main_location
-- create function public.update_partner_company_and_main_location

create function public.check_partner_company_location_duplicate_vat_id_no()
returns trigger as $$
begin
  if exists (
    with new_partner_company as (
      select client_company_id from public.partner_company
      where partner_company.id = new.partner_company_id
    )
    select from new_partner_company, public.partner_company
      inner join public.company_location on company_location.partner_company_id = partner_company.id
    where partner_company.client_company_id = new_partner_company.client_company_id
    and company_location.partner_company_id <> new.partner_company_id
    and company_location.vat_id_no = new.vat_id_no
  ) then
    if private.current_user_language() = 'de'
      then raise exception 'Ein Geschäftspartner mit identer UID-Nummer existiert bereits!';
    end if;

    raise exception 'Partner company with the same VAT-ID already exists!';
  end if;
  return new;
end
$$ language plpgsql stable;

create trigger check_partner_company_location_duplicate_vat_id_no
  before insert or update on public.company_location
  for each row
  when (private.current_user_id() is not null and new.partner_company_id is not null and new.vat_id_no is not null)
  execute procedure public.check_partner_company_location_duplicate_vat_id_no();
