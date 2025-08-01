alter table public.partner_company
add column main_client_company_cost_center_id uuid references public.client_company_cost_center(id) on delete set null;
alter table public.partner_company
add column main_client_company_cost_unit_id   uuid references public.client_company_cost_unit(id) on delete set null;

create index partner_company_main_client_company_cost_center_id_idx on public.partner_company (main_client_company_cost_center_id);
create index partner_company_main_client_company_cost_unit_id_idx on public.partner_company (main_client_company_cost_unit_id);

----

-- TODO: clone when cloning client company
create table public.partner_company_cost_center (
  id uuid primary key default uuid_generate_v4(),

  partner_company_id uuid not null references public.partner_company(id) on delete cascade,
  client_company_cost_center_id uuid not null references public.client_company_cost_center(id) on delete cascade,
  unique(partner_company_id, client_company_cost_center_id),

  -- TODO: implement "main" column and remove the partner_company columns
  -- main boolean not null default false,

  created_at timestamptz not null default now()
);
grant select, insert, update, delete on table public.partner_company_cost_center to domonda_user;
grant select on table public.partner_company_cost_center to domonda_wg_user; -- TODO: just select I guess?
create index partner_company_cost_center_partner_company_id_idx on public.partner_company_cost_center (partner_company_id);
create index partner_company_cost_center_client_company_cost_center_id_idx on public.partner_company_cost_center (client_company_cost_center_id);

-- TODO: clone when cloning client company
create table public.partner_company_cost_unit (
  id uuid primary key default uuid_generate_v4(),

  partner_company_id uuid not null references public.partner_company(id) on delete cascade,
  client_company_cost_unit_id uuid not null references public.client_company_cost_unit(id) on delete cascade,
  unique(partner_company_id, client_company_cost_unit_id),

  -- TODO: implement "main" column and remove the partner_company columns
  -- main boolean not null default false,

  created_at timestamptz not null default now()
);
grant select, insert, update, delete on table public.partner_company_cost_unit to domonda_user;
grant select on table public.partner_company_cost_unit to domonda_wg_user; -- TODO: just select I guess?
create index partner_company_cost_unit_partner_company_id_idx on public.partner_company_cost_unit (partner_company_id);
create index partner_company_cost_unit_client_company_cost_unit_id_idx on public.partner_company_cost_unit (client_company_cost_unit_id);

----

create function public.create_partner_company(
  client_company_id                  uuid,
  company_id                         uuid = null,
  name                               text = null,
  alternative_names                  text[] = '{}',
  paid_with_direct_debit             boolean = false,
  notes                              non_empty_text = null,
  main_client_company_cost_center_id uuid = null,
  main_client_company_cost_unit_id   uuid = null,
  client_company_cost_center_ids     uuid[] = '{}',
  client_company_cost_unit_ids       uuid[] = '{}',
  active                             boolean = true
) returns public.partner_company as $$
declare
  inserted_partner_company public.partner_company;
  client_company_cost_center_id uuid;
  client_company_cost_unit_id uuid;
begin
  insert into public.partner_company (
    client_company_id,
    company_id,
    name,
    alternative_names,
    paid_with_direct_debit,
    notes,
    source,
    main_client_company_cost_center_id,
    main_client_company_cost_unit_id,
    disabled_by,
    disabled_at
  ) values (
    create_partner_company.client_company_id,
    create_partner_company.company_id,
    create_partner_company.name,
    create_partner_company.alternative_names,
    create_partner_company.paid_with_direct_debit,
    create_partner_company.notes,
    'USER_CREATE',
    create_partner_company.main_client_company_cost_center_id,
    create_partner_company.main_client_company_cost_unit_id,
    (case when active then null else private.current_user_id() end),
    (case when active then null else now() end)
  )
  returning * into inserted_partner_company;

  foreach client_company_cost_center_id in array client_company_cost_center_ids loop
    if client_company_cost_center_id = inserted_partner_company.main_client_company_cost_center_id
    then
      raise exception 'Main cost center cannot be in additional cost centers too.';
    end if;

    insert into public.partner_company_cost_center (partner_company_id, client_company_cost_center_id)
    values (inserted_partner_company.id, client_company_cost_center_id);
  end loop;

  foreach client_company_cost_unit_id in array client_company_cost_unit_ids loop
    if client_company_cost_unit_id = inserted_partner_company.main_client_company_cost_unit_id
    then
      raise exception 'Main cost unit cannot be in additional cost units too.';
    end if;

    insert into public.partner_company_cost_unit (partner_company_id, client_company_cost_unit_id)
    values (inserted_partner_company.id, client_company_cost_unit_id);
  end loop;

  return inserted_partner_company;
end
$$ language plpgsql volatile;

----

create function public.update_partner_company(
  id                                 uuid,
  company_id                         uuid = null,
  name                               text = null,
  alternative_names                  text[] = '{}',
  paid_with_direct_debit             boolean = false,
  notes                              non_empty_text = null,
  main_client_company_cost_center_id uuid = null,
  main_client_company_cost_unit_id   uuid = null,
  client_company_cost_center_ids     uuid[] = '{}',
  client_company_cost_unit_ids       uuid[] = '{}',
  active                             boolean = true
) returns public.partner_company as $$
declare
  updated_partner_company public.partner_company;
  client_company_cost_center_id uuid;
  client_company_cost_unit_id uuid;
begin
  update public.partner_company
    set
      company_id=update_partner_company.company_id,
      name=update_partner_company.name,
      alternative_names=update_partner_company.alternative_names,
      paid_with_direct_debit=update_partner_company.paid_with_direct_debit,
      notes=update_partner_company.notes,
      main_client_company_cost_center_id=update_partner_company.main_client_company_cost_center_id,
      main_client_company_cost_unit_id=update_partner_company.main_client_company_cost_unit_id,
      disabled_by=(case when active then null else private.current_user_id() end),
      disabled_at=(case when active then null else now() end),
      updated_at=now()
  where partner_company.id = update_partner_company.id
  returning * into updated_partner_company;

  foreach client_company_cost_center_id in array client_company_cost_center_ids loop
    if client_company_cost_center_id = updated_partner_company.main_client_company_cost_center_id
    then
      raise exception 'Main cost center cannot be in additional cost centers too.';
    end if;

    insert into public.partner_company_cost_center (partner_company_id, client_company_cost_center_id)
    values (updated_partner_company.id, client_company_cost_center_id)
    on conflict do nothing;
  end loop;
  delete from public.partner_company_cost_center
  where partner_company_cost_center.partner_company_id = updated_partner_company.id
  and partner_company_cost_center.client_company_cost_center_id != all(client_company_cost_center_ids);

  foreach client_company_cost_unit_id in array client_company_cost_unit_ids loop
    if client_company_cost_unit_id = updated_partner_company.main_client_company_cost_unit_id
    then
      raise exception 'Main cost unit cannot be in additional cost units too.';
    end if;

    insert into public.partner_company_cost_unit (partner_company_id, client_company_cost_unit_id)
    values (updated_partner_company.id, client_company_cost_unit_id)
    on conflict do nothing;
  end loop;
  delete from public.partner_company_cost_unit
  where partner_company_cost_unit.partner_company_id = updated_partner_company.id
  and partner_company_cost_unit.client_company_cost_unit_id != all(client_company_cost_unit_ids);

  return updated_partner_company;
end;
$$
language plpgsql volatile;

----

create function public.create_partner_company_and_main_location(
  client_company_id                  uuid,
  country                            country_code,
  company_id                         uuid = null,
  name                               text = null,
  alternative_names                  text[] = '{}',
  paid_with_direct_debit             boolean = false,
  notes                              non_empty_text = null,
  main_client_company_cost_center_id uuid = null,
  main_client_company_cost_unit_id   uuid = null,
  client_company_cost_center_ids     uuid[] = '{}',
  client_company_cost_unit_ids       uuid[] = '{}',
  active                             boolean = true,
  street                             non_empty_text = null,
  city                               non_empty_text = null,
  zip                                non_empty_text = null,
  phone                              non_empty_text = null,
  email                              public.email_addr = null,
  website                            non_empty_text = null,
  registration_no                    non_empty_text = null,
  tax_id_no                          non_empty_text = null,
  vat_id_no                          public.vat_id = null
) returns public.partner_company as $$
declare
  inserted_partner_company public.partner_company;
begin
  inserted_partner_company := public.create_partner_company(
    client_company_id=>create_partner_company_and_main_location.client_company_id,
    company_id=>create_partner_company_and_main_location.company_id,
    name=>create_partner_company_and_main_location.name,
    alternative_names=>create_partner_company_and_main_location.alternative_names,
    paid_with_direct_debit=>create_partner_company_and_main_location.paid_with_direct_debit,
    notes=>create_partner_company_and_main_location.notes,
    main_client_company_cost_center_id=>create_partner_company_and_main_location.main_client_company_cost_center_id,
    main_client_company_cost_unit_id=>create_partner_company_and_main_location.main_client_company_cost_unit_id,
    client_company_cost_center_ids=>create_partner_company_and_main_location.client_company_cost_center_ids,
    client_company_cost_unit_ids=>create_partner_company_and_main_location.client_company_cost_unit_ids,
    active=>create_partner_company_and_main_location.active
  );

  -- if the user supplied different values from the linked main, create new location
  if coalesce((select
      create_partner_company_and_main_location.country is distinct from company_location.country
      or create_partner_company_and_main_location.street is distinct from company_location.street
      or create_partner_company_and_main_location.city is distinct from company_location.city
      or create_partner_company_and_main_location.zip is distinct from company_location.zip
      or create_partner_company_and_main_location.phone is distinct from company_location.phone
      or create_partner_company_and_main_location.email is distinct from company_location.email
      or create_partner_company_and_main_location.website is distinct from company_location.website
      or create_partner_company_and_main_location.registration_no is distinct from company_location.registration_no
      or create_partner_company_and_main_location.tax_id_no is distinct from company_location.tax_id_no
      or create_partner_company_and_main_location.vat_id_no is distinct from company_location.vat_id_no
    from public.company_location
    where create_partner_company_and_main_location.company_id = company_location.company_id
    and main), true) -- consider no company too
  then
    insert into public.company_location (partner_company_id, main, street, city, zip, country, phone, email, website, registration_no, tax_id_no, vat_id_no)
      values (
        inserted_partner_company.id,
        true,
        create_partner_company_and_main_location.street,
        create_partner_company_and_main_location.city,
        create_partner_company_and_main_location.zip,
        create_partner_company_and_main_location.country,
        create_partner_company_and_main_location.phone,
        create_partner_company_and_main_location.email,
        create_partner_company_and_main_location.website,
        create_partner_company_and_main_location.registration_no,
        create_partner_company_and_main_location.tax_id_no,
        create_partner_company_and_main_location.vat_id_no
      );
  end if;

  return inserted_partner_company;
end;
$$ language plpgsql volatile;

----

create function public.update_partner_company_and_main_location(
  partner_company_id                 uuid,
  country                            country_code,
  company_id                         uuid = null,
  name                               text = null,
  alternative_names                  text[] = '{}',
  paid_with_direct_debit             boolean = false,
  notes                              non_empty_text = null,
  main_client_company_cost_center_id uuid = null,
  main_client_company_cost_unit_id   uuid = null,
  client_company_cost_center_ids     uuid[] = '{}',
  client_company_cost_unit_ids       uuid[] = '{}',
  active                             boolean = true,
  street                             non_empty_text = null,
  city                               non_empty_text = null,
  zip                                non_empty_text = null,
  phone                              non_empty_text = null,
  email                              public.email_addr = null,
  website                            non_empty_text = null,
  registration_no                    non_empty_text = null,
  tax_id_no                          non_empty_text = null,
  vat_id_no                          public.vat_id = null
) returns public.partner_company as $$
declare
  updated_partner_company public.partner_company;
begin
  updated_partner_company := public.update_partner_company(
    id=>update_partner_company_and_main_location.partner_company_id,
    company_id=>update_partner_company_and_main_location.company_id,
    name=>update_partner_company_and_main_location.name,
    alternative_names=>update_partner_company_and_main_location.alternative_names,
    paid_with_direct_debit=>update_partner_company_and_main_location.paid_with_direct_debit,
    notes=>update_partner_company_and_main_location.notes,
    main_client_company_cost_center_id=>update_partner_company_and_main_location.main_client_company_cost_center_id,
    main_client_company_cost_unit_id=>update_partner_company_and_main_location.main_client_company_cost_unit_id,
    client_company_cost_center_ids=>update_partner_company_and_main_location.client_company_cost_center_ids,
    client_company_cost_unit_ids=>update_partner_company_and_main_location.client_company_cost_unit_ids,
    active=>update_partner_company_and_main_location.active
  );

  if coalesce((select
      update_partner_company_and_main_location.country is distinct from company_location.country
      or update_partner_company_and_main_location.street is distinct from company_location.street
      or update_partner_company_and_main_location.city is distinct from company_location.city
      or update_partner_company_and_main_location.zip is distinct from company_location.zip
      or update_partner_company_and_main_location.phone is distinct from company_location.phone
      or update_partner_company_and_main_location.email is distinct from company_location.email
      or update_partner_company_and_main_location.website is distinct from company_location.website
      or update_partner_company_and_main_location.registration_no is distinct from company_location.registration_no
      or update_partner_company_and_main_location.tax_id_no is distinct from company_location.tax_id_no
      or update_partner_company_and_main_location.vat_id_no is distinct from company_location.vat_id_no
    from public.company_location
    where update_partner_company_and_main_location.company_id = company_location.company_id
    and main), true) -- consider no company too
  then
    if exists (
      select from public.company_location
      where update_partner_company_and_main_location.partner_company_id = company_location.partner_company_id
      and main
    ) then
      update public.company_location set
        street=update_partner_company_and_main_location.street,
        city=update_partner_company_and_main_location.city,
        zip=update_partner_company_and_main_location.zip,
        country=update_partner_company_and_main_location.country,
        phone=update_partner_company_and_main_location.phone,
        email=update_partner_company_and_main_location.email,
        website=update_partner_company_and_main_location.website,
        registration_no=update_partner_company_and_main_location.registration_no,
        tax_id_no=update_partner_company_and_main_location.tax_id_no,
        vat_id_no=update_partner_company_and_main_location.vat_id_no,
        updated_at=now()
      where update_partner_company_and_main_location.partner_company_id = company_location.partner_company_id
      and main;
    else
      insert into public.company_location (partner_company_id, main, street, city, zip, country, phone, email, website, registration_no, tax_id_no, vat_id_no)
      values (
        updated_partner_company.id,
        true,
        update_partner_company_and_main_location.street,
        update_partner_company_and_main_location.city,
        update_partner_company_and_main_location.zip,
        update_partner_company_and_main_location.country,
        update_partner_company_and_main_location.phone,
        update_partner_company_and_main_location.email,
        update_partner_company_and_main_location.website,
        update_partner_company_and_main_location.registration_no,
        update_partner_company_and_main_location.tax_id_no,
        update_partner_company_and_main_location.vat_id_no
      );
    end if;
  end if;

  return updated_partner_company;
end;
$$ language plpgsql volatile;

----

create function private.invoice_partner_company_cost_centers_and_units() returns trigger as $$
declare
  invoice public.invoice := new;
begin
  if invoice.net is not null
  and not exists (select from public.invoice_cost_center
    where invoice_cost_center.document_id = invoice.document_id)
  then
    -- only if there are no existing cost centers assigned, assign the main one
    insert into public.invoice_cost_center (document_id, client_company_cost_center_id, amount)
    select invoice.document_id, partner_company.main_client_company_cost_center_id, invoice.net
    from public.partner_company
    where partner_company.id = invoice.partner_company_id
    and partner_company.main_client_company_cost_center_id is not null;

    if exists (select from public.partner_company_cost_center
      where partner_company_cost_center.partner_company_id = invoice.partner_company_id)
    then
      -- if there are other cost centers assigned to the partner company, assign them to the invoice and set all of the amounts to 0
      insert into public.invoice_cost_center (document_id, client_company_cost_center_id, amount)
      select invoice.document_id, partner_company_cost_center.client_company_cost_center_id, 0
      from public.partner_company_cost_center
      where partner_company_cost_center.partner_company_id = invoice.partner_company_id;

      update public.invoice_cost_center
      set amount=0
      where invoice_cost_center.document_id = invoice.document_id;
    end if;
  end if;

  if invoice.net is not null
  and not exists (select from public.invoice_cost_unit
    where invoice_cost_unit.invoice_document_id = invoice.document_id)
  then
    -- only if there are no existing cost units assigned, assign the main one
    insert into public.invoice_cost_unit (invoice_document_id, client_company_cost_unit_id, amount)
    select invoice.document_id, partner_company.main_client_company_cost_unit_id, invoice.net
    from public.partner_company
    where partner_company.id = invoice.partner_company_id
    and partner_company.main_client_company_cost_unit_id is not null;

    if exists (select from public.partner_company_cost_unit
      where partner_company_cost_unit.partner_company_id = invoice.partner_company_id)
    then
      -- if there are other cost units assigned to the partner company, assign them to the invoice and set all of the amounts to 0
      insert into public.invoice_cost_unit (invoice_document_id, client_company_cost_unit_id, amount)
      select invoice.document_id, partner_company_cost_unit.client_company_cost_unit_id, 0
      from public.partner_company_cost_unit
      where partner_company_cost_unit.partner_company_id = invoice.partner_company_id;

      update public.invoice_cost_unit
      set amount=0
      where invoice_document_id = invoice.document_id;
    end if;
  end if;

  return new;
end
$$ language plpgsql volatile strict;

create trigger invoice_partner_company_cost_centers_and_units_insert
  after insert on public.invoice
  for each row
  execute procedure private.invoice_partner_company_cost_centers_and_units();

create trigger invoice_partner_company_cost_centers_and_units_update
  after update on public.invoice
  for each row
  when (
    old.partner_company_id is distinct from new.partner_company_id
    or old.net is distinct from new.net
  )
  execute procedure private.invoice_partner_company_cost_centers_and_units();
