create function public.client_company_has_ger_clause_35a_invoices(
  client_company public.client_company
) returns boolean as $$
  select public.is_company_feature_active('IDWELL', client_company.company_id)
    -- subquery to make sure the funciton never returns null
    and exists (
      select from public.company_location
      where company_location.company_id = client_company.company_id
      and company_location.main
      and company_location.country = 'DE'
    )
$$ language sql stable strict;

comment on function public.client_company_has_ger_clause_35a_invoices is '@notNull';

----

create view public.real_estate_object_type as (
  select
    "option"   as "type",
    null::text as "description"
  from object.class_prop,
    unnest(class_prop.options) as "option"
  where "class_name" = 'RealEstateObject'
    and "name" = 'Objekttyp'
);

comment on view public.real_estate_object_type is $$
@enum
@primaryKey "type"
$$;

grant select on table public.real_estate_object_type to domonda_user;
grant select on table public.real_estate_object_type to domonda_wg_user;

create domain public.real_estate_object_type_enum_domain as text;

-- The domain above creates a type for a dynamic enum that resembles:
-- create type public.real_estate_object_type as enum (
--   'WEG',
--   'HI',
--   'SUB',
--   'KREIS',
--   'MANDANT'
-- );


----

create view public.real_estate_object as (
  select
    instance.id,
    instance.client_company_id,
    instance.created_at,
    instance.created_by,
    instance.disabled_at,
    instance.disabled_by,
    instance.disabled_at is null as "active",
    (
      select class_prop.options[text_option_prop.option_index+1]::real_estate_object_type_enum_domain
      from object.text_option_prop
        inner join object.class_prop
        on class_prop.id = text_option_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Objekttyp'
      where text_option_prop.instance_id = instance.id
    ) as "type",
    (
      select account_no_prop.value
      from object.account_no_prop
        inner join object.class_prop
        on class_prop.id = account_no_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Objektnummer'
      where account_no_prop.instance_id = instance.id
    ) as "number",
    (
      select account_no_prop.value
      from object.account_no_prop
        inner join object.class_prop
        on class_prop.id = account_no_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Kreis'
      where account_no_prop.instance_id = instance.id
    ) as "accounting_area",
    (
      select account_no_prop.value
      from object.account_no_prop
        inner join object.class_prop
        on class_prop.id = account_no_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Mandant'
      where account_no_prop.instance_id = instance.id
    ) as "user_account",
    (
      select text_prop.value
      from object.text_prop
        inner join object.class_prop
        on class_prop.id = text_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Anmerkungen'
      where text_prop.instance_id = instance.id
    ) as "note",
    (
      select text_prop.value
      from object.text_prop
        inner join object.class_prop
        on class_prop.id = text_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Straßenadresse'
      where text_prop.instance_id = instance.id
    ) as "address",
    (
      select array_agg(text_prop.value)
      from object.text_prop
        inner join object.class_prop
        on class_prop.id = text_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Alternative Straßenadressen'
      where text_prop.instance_id = instance.id
    ) as "alternative_addresses",
    (
      select text_prop.value
      from object.text_prop
        inner join object.class_prop
        on class_prop.id = text_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Postleitzahl'
      where text_prop.instance_id = instance.id
    ) as "zip",
    (
      select text_prop.value
      from object.text_prop
        inner join object.class_prop
        on class_prop.id = text_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Ort'
      where text_prop.instance_id = instance.id
    ) as "city",
    (
      select country_prop.value
      from object.country_prop
        inner join object.class_prop
        on class_prop.id = country_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Land'
      where country_prop.instance_id = instance.id
    ) as "country",
    (
      select iban_prop.value
      from object.iban_prop
        inner join object.class_prop
        on class_prop.id = iban_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'IBAN'
      where iban_prop.instance_id = instance.id
    ) as "iban",
    (
      select bic_prop.value
      from object.bic_prop
        inner join object.class_prop
        on class_prop.id = bic_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'BIC'
      where bic_prop.instance_id = instance.id
    ) as "bic",
    (
      select array_agg(object.bank_account_prop_value(bank_account_prop) order by array_index)
      from object.bank_account_prop
        inner join object.class_prop
        on class_prop.id = bank_account_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Bankverbindungen'
      where bank_account_prop.instance_id = instance.id
    ) as "bank_accounts"
  from object.instance
    inner join object.class on class.name = 'RealEstateObject'
  where instance.class_name = class.name
);

grant select on public.real_estate_object to domonda_user;
grant select on public.real_estate_object to domonda_wg_user;

comment on column public.real_estate_object.id is '@notNull';
comment on column public.real_estate_object.client_company_id is '@notNull';
comment on column public.real_estate_object.created_at is '@notNull';
comment on column public.real_estate_object.created_by is '@notNull';
comment on column public.real_estate_object.type is '@notNull';
comment on column public.real_estate_object.number is '@notNull';
comment on column public.real_estate_object.address is null; -- TODO: revert to @notNull
comment on column public.real_estate_object.zip is null; -- TODO: revert to @notNull
comment on column public.real_estate_object.country is null; -- TODO: revert to @notNull when all real-estate-objects in the database have a country
comment on view public.real_estate_object is $$
@primaryKey id
@foreignKey (client_company_id) references public.client_company (company_id)
@foreignKey ("type") references public.real_estate_object_type ("type")
$$;

----

create function public.real_estate_object_title(
  real_estate_object public.real_estate_object
) returns trimmed_text as $$
  select trim(
    real_estate_object.number || ' / ' ||
    real_estate_object.type || ' / ' ||
    coalesce(real_estate_object.note || ' / ', '') ||
    coalesce(real_estate_object.zip || ' ', '') ||
    coalesce(real_estate_object.address, '')
  )
$$ language sql immutable strict;

comment on function public.real_estate_object_title is '@notNull';


create function private.real_estate_object_fulltext(
  real_estate_object public.real_estate_object
) returns text as $$
    select trim(
      real_estate_object.number || ' ' ||
      real_estate_object.type || ' ' ||
      coalesce(real_estate_object.note, '') || ' ' ||
      coalesce(real_estate_object.zip, '') || ' ' ||
      coalesce(real_estate_object.address, '') || ' ' ||
      coalesce(array_to_string(real_estate_object.alternative_addresses, ' '), '')
    )
$$ language sql immutable strict;


create function public.update_real_estate_object(
    id                     uuid,
    "type"                 real_estate_object_type_enum_domain,
    "number"               account_no,
    address                text,
    zip                    text,
    country                country_code,
    accounting_area        account_no = null,
    user_account           account_no = null,
    alternative_addresses  text[] = null,
    city                   text = null,
    iban                   bank_iban = null,
    bic                    bank_bic = null,
    note                   trimmed_text = null,
    client_company_tag_ids uuid[] = null,
    active                 boolean = true,
    updated_by             trimmed_text = private.current_user_id()::trimmed_text
  ) returns public.real_estate_object
language plpgsql volatile as $$
declare
    update_object public.real_estate_object;
begin
    if not exists (select from object.instance where instance.id = update_real_estate_object.id) then
        raise exception 'Real estate object with ID % does not exist', id;
    end if;

    perform object.update_instance_active(id, coalesce(active, true), updated_by);

    perform object.update_text_option_prop(id, 'Objekttyp', "type", updated_by);
    perform object.update_account_no_prop(id, 'Objektnummer', "number", updated_by);
    perform object.update_account_no_prop(id, 'Kreis', accounting_area, updated_by);
    perform object.update_account_no_prop(id, 'Mandant', user_account, updated_by);
    perform object.update_text_prop(id, 'Straßenadresse', address, updated_by);
    perform object.update_text_array_prop(id, 'Alternative Straßenadressen', alternative_addresses, updated_by);
    perform object.update_text_prop(id, 'Postleitzahl', zip, updated_by);
    perform object.update_text_prop(id, 'Ort', city, updated_by);
    perform object.update_country_prop(id, 'Land', country, updated_by);
    perform object.update_iban_prop(id, 'IBAN', iban, updated_by);
    perform object.update_bic_prop(id, 'BIC', bic, updated_by);
    perform object.update_text_prop(id, 'Anmerkungen', note, updated_by);

    -- client_company_tag_ids (Tags)
    -- TODO: update only changed tags
    delete from public.real_estate_object_client_company_tag where object_instance_id = id;
    if client_company_tag_ids is not null then
        insert into public.real_estate_object_client_company_tag (object_instance_id, client_company_tag_id, created_by)
        select id, client_company_tag_id, updated_by
        from unnest(client_company_tag_ids) as client_company_tag_id;
    end if;

    select * into update_object
    from public.real_estate_object
    where real_estate_object.id = update_real_estate_object.id;

    return update_object;
end
$$;

create function public.create_real_estate_object(
    client_company_id      uuid,
    "type"                 real_estate_object_type_enum_domain,
    "number"               account_no,
    address                text,
    zip                    text,
    country                country_code,
    accounting_area        account_no = null,
    user_account           account_no = null,
    alternative_addresses  text[] = null,
    city                   text = null,
    iban                   bank_iban = null,
    bic                    bank_bic = null,
    note                   trimmed_text = null,
    client_company_tag_ids uuid[] = null,
    active                 boolean = true,
    created_by             trimmed_text = private.current_user_id()::trimmed_text
) returns public.real_estate_object
language sql volatile as $$
    with new_instance as (
        insert into object.instance (client_company_id, class_name, created_by)
        values (client_company_id, 'RealEstateObject', created_by)
        returning id
    )
    select public.update_real_estate_object(
        (select id from new_instance),
        "type",
        "number",
        address,
        zip,
        country,
        accounting_area,
        user_account,
        alternative_addresses,
        city,
        iban,
        bic,
        note,
        client_company_tag_ids,
        active,
        created_by
    )
$$;

----

create function public.delete_real_estate_object(
    id uuid
) returns public.real_estate_object
language plpgsql volatile as $$
declare
    deleted public.real_estate_object;
begin
    select * into deleted
    from public.real_estate_object
    where real_estate_object.id = delete_real_estate_object.id;

    delete from object.instance
    where instance.id = delete_real_estate_object.id;

    return deleted;
end
$$;

----

create function public.client_company_real_estate_objects(
    client_company public.client_company
) returns setof public.real_estate_object
language sql stable as $$
    select * from public.real_estate_object
    where real_estate_object.client_company_id = client_company.company_id
$$;

----

create function public.filter_real_estate_objects(
    client_company_id uuid,
    search_text       text = null,
    only_active       boolean = true
) returns setof public.real_estate_object
language sql stable as $$
    select * from public.real_estate_object
    -- NOTE: performance can be not so great with this text search
    where real_estate_object.client_company_id = filter_real_estate_objects.client_company_id
    and (not only_active or real_estate_object.active)
    and (
        search_text is null
        or
        public.real_estate_object_title(real_estate_object) ilike '%'||search_text||'%'
    )
    order by real_estate_object.number collate "numeric" desc
$$;

----

create function public.real_estate_objects_by_ids(
    ids uuid[]
) returns setof public.real_estate_object
language sql stable strict as $$
    select * from public.real_estate_object
    where id = any(ids)
$$;

----

-- See also public.document_object_instance for generic DMS functionality.
-- We keep this REO specific table because other hard coded functionality
-- has been implemented on top of it.
create table public.document_real_estate_object (
  -- document_id is primary key because a document can have only one object.instance assigned
  document_id uuid primary key references public.document(id) on delete cascade,

  object_instance_id uuid not null references object.instance(id) on delete cascade,

  updated_by trimmed_text not null,
  updated_at timestamptz  not null default now(),
  created_by trimmed_text not null,
  created_at timestamptz  not null default now()
);

grant all on public.document_real_estate_object to domonda_user;
grant select on table public.document_real_estate_object to domonda_wg_user;

create index document_real_estate_object_object_instance_id_idx on public.document_real_estate_object (object_instance_id);


create trigger insert_document_real_estate_object_update_doc_searchtext
  after insert on public.document_real_estate_object
  for each row
  execute procedure private.document_update_fulltext_and_searchtext();
create trigger delete_document_real_estate_object_update_doc_searchtext
  after delete on public.document_real_estate_object
  for each row
  execute procedure private.document_update_fulltext_and_searchtext();
create trigger update_document_real_estate_object_update_doc_searchtext
  after update on public.document_real_estate_object
  for each row
  when (
    old.object_instance_id is distinct from new.object_instance_id
  )
  execute procedure private.document_update_fulltext_and_searchtext();

-- TODO idwell: create trigger for document fulltext when object props change


create function public.document_real_estate_object_real_estate_object(
  document_real_estate_object public.document_real_estate_object
) returns public.real_estate_object
language sql stable as $$
  select * from public.real_estate_object
  where real_estate_object.id = document_real_estate_object.object_instance_id
$$;

comment on function public.document_real_estate_object_real_estate_object is '@notNull';


create function public.document_real_estate_object(
  document public.document
) returns public.real_estate_object
language sql stable as $$
  select public.document_real_estate_object_real_estate_object(document_real_estate_object)
  from public.document_real_estate_object
  where document_real_estate_object.document_id = document.id
$$;

create function public.document_real_estate_object_last_edit_by(
  document public.document
) returns public.user as $$
    select user_for_invoice_confirmed_by.* from
      public.document_real_estate_object,
      private.user_for_invoice_confirmed_by(coalesce(
        document_real_estate_object.updated_by,
        document_real_estate_object.created_by
      ))
    where document_real_estate_object.document_id = document.id
$$ language sql stable strict;

create function public.document_real_estate_object_last_edit_at(
  document public.document
) returns timestamptz as $$
    select coalesce(document_real_estate_object.updated_at, document_real_estate_object.created_at)
    from public.document_real_estate_object
    where document_real_estate_object.document_id = document.id
$$ language sql stable strict;

create function public.set_document_real_estate_object(
  document_id           uuid,
  real_estate_object_id uuid = null
) returns public.document_real_estate_object
language plpgsql volatile as $$
declare
  changed_document_real_estate_object public.document_real_estate_object;
begin
  if real_estate_object_id is null
  then
    delete from public.document_real_estate_object
    where document_real_estate_object.document_id = set_document_real_estate_object.document_id
    returning * into changed_document_real_estate_object;
    return changed_document_real_estate_object;
  end if;

  -- cannot use on conflict (document_id) because document_id is ambiguous
  if exists (select from public.document_real_estate_object
    where document_real_estate_object.document_id = set_document_real_estate_object.document_id)
  then
    update public.document_real_estate_object
      set
        object_instance_id=set_document_real_estate_object.real_estate_object_id,
        updated_by=private.current_user_id(),
        updated_at=now()
    where document_real_estate_object.document_id = set_document_real_estate_object.document_id
    returning * into changed_document_real_estate_object;
    return changed_document_real_estate_object;
  end if;

  insert into public.document_real_estate_object (
    document_id,
    object_instance_id,
    updated_by,
    created_by
  ) values (
    set_document_real_estate_object.document_id,
    set_document_real_estate_object.real_estate_object_id,
    private.current_user_id(),
    private.current_user_id()
  )
  returning * into changed_document_real_estate_object;
  return changed_document_real_estate_object;
end
$$;


create function public.real_estate_object_documents(
  real_estate_object public.real_estate_object
) returns setof public.document
language sql stable strict as $$
  select document.* from public.document
    inner join public.document_real_estate_object on document_real_estate_object.document_id = document.id
  where document_real_estate_object.object_instance_id = real_estate_object.id
$$;

----

-- TODO replace by object.prop_type 'GENERAL_LEDGER_ACCOUNT'
create table public.real_estate_object_general_ledger_account (
    object_instance_id        uuid not null references object.instance(id)               on delete cascade,
    general_ledger_account_id uuid not null references public.general_ledger_account(id) on delete cascade,
    primary key(object_instance_id, general_ledger_account_id),

    created_by trimmed_text not null,
    created_at timestamptz  not null default now()
);

grant all on public.real_estate_object_general_ledger_account to domonda_user;
grant select on table public.real_estate_object_general_ledger_account to domonda_wg_user;

create index real_estate_object_instance_id_idx on public.real_estate_object_general_ledger_account(object_instance_id);
create index real_estate_object_account_id_idx  on public.real_estate_object_general_ledger_account(general_ledger_account_id);


create function public.real_estate_object_general_ledger_account(
  real_estate_object public.real_estate_object
) returns public.general_ledger_account
language sql stable strict as $$
  select general_ledger_account.* from public.real_estate_object_general_ledger_account as t_real_estate_object_general_ledger_account
    inner join public.general_ledger_account on general_ledger_account.id = t_real_estate_object_general_ledger_account.general_ledger_account_id
  where t_real_estate_object_general_ledger_account.object_instance_id = real_estate_object.id
$$;

comment on function public.real_estate_object_general_ledger_account is '@deprecated Use `RealEstateObject.generalLedgerAccounts` instead.';


create function public.real_estate_object_general_ledger_accounts(
  real_estate_object public.real_estate_object
) returns setof public.general_ledger_account
language sql stable strict as $$
  select general_ledger_account.* from public.real_estate_object_general_ledger_account as t_real_estate_object_general_ledger_account
    inner join public.general_ledger_account on general_ledger_account.id = t_real_estate_object_general_ledger_account.general_ledger_account_id
  where t_real_estate_object_general_ledger_account.object_instance_id = real_estate_object.id
  order by public.general_ledger_account_number_as_number(general_ledger_account)
$$;


create function public.general_ledger_account_has_real_estate_object_by_id(
  general_ledger_account public.general_ledger_account,
  real_estate_object_id  uuid = null -- we allow nulls because of how AutocompleteGeneralLedgerAccountWithSuggestions
) returns boolean
language sql stable as $$
  select exists (
    select from public.real_estate_object_general_ledger_account
      inner join public.real_estate_object on real_estate_object.id = real_estate_object_general_ledger_account.object_instance_id
    where real_estate_object_general_ledger_account.general_ledger_account_id = general_ledger_account.id
    and real_estate_object.id = real_estate_object_id
  )
$$;

comment on function public.general_ledger_account_has_real_estate_object_by_id is '@notNull';

----

-- TODO replace by object.prop_type 'PARTNER_ACCOUNT'
create table public.real_estate_object_partner_account (
    object_instance_id uuid not null references object.instance(id)        on delete cascade,
    partner_account_id uuid not null references public.partner_account(id) on delete cascade,
    primary key(object_instance_id, partner_account_id),

    created_by trimmed_text not null,
    created_at timestamptz  not null default now()
);

grant all on public.real_estate_object_partner_account to domonda_user;
grant select on table public.real_estate_object_partner_account to domonda_wg_user;

create index real_estate_object_partner_instance_id_idx on public.real_estate_object_partner_account(object_instance_id);
create index real_estate_object_partner_account_id_idx  on public.real_estate_object_partner_account(partner_account_id);

create function public.real_estate_object_partner_account(
  real_estate_object public.real_estate_object
) returns public.partner_account
language sql stable strict as $$
  select partner_account.* from public.real_estate_object_partner_account as t_real_estate_object_partner_account
    inner join public.partner_account on partner_account.id = t_real_estate_object_partner_account.partner_account_id
  where t_real_estate_object_partner_account.object_instance_id = real_estate_object.id
$$;

----

create function public.invoice_payment_preferred_bank_account(
    invoice public.invoice
) returns public.bank_account
language sql stable strict as $$
    select coalesce(
        (
          select bank_account
          from public.document_real_estate_object,
            public.document_real_estate_object_real_estate_object(document_real_estate_object) as real_estate_object
          inner join public.document on document.id = invoice.document_id
          inner join public.bank_account
              on bank_account.iban = real_estate_object.iban
              and bank_account.client_company_id = document.client_company_id
          where document_real_estate_object.document_id = document.id
        ),
        (
          select bank_account from public.bank_account
          where id = (public.primary_or_newest_currency_payment_preset_for_partner_company(invoice.partner_company_id, invoice.currency)).bank_account_id
        )
    )
$$;

----

-- TODO introduce TAG_ARRAY prop type to replace this table
create table public.real_estate_object_client_company_tag (
  -- TODO: make sure that the instance is of class RealEstateObject
  object_instance_id    uuid not null references object.instance(id)           on delete cascade,
  client_company_tag_id uuid not null references public.client_company_tag(id) on delete cascade,
  primary key(object_instance_id, client_company_tag_id),

  created_by trimmed_text not null,
  created_at timestamptz  not null default now()
);

grant all on public.real_estate_object_client_company_tag to domonda_user;
grant select on table public.real_estate_object_client_company_tag to domonda_wg_user;

create index real_estate_object_client_company_tag_object_instance_id_idx on public.real_estate_object_client_company_tag(object_instance_id);
create index real_estate_object_client_company_tag_client_company_tag_id_idx on public.real_estate_object_client_company_tag(client_company_tag_id);

create function public.real_estate_object_client_company_tags(
  real_estate_object public.real_estate_object
) returns setof public.client_company_tag as $$
  select client_company_tag.* from public.real_estate_object_client_company_tag
    inner join public.client_company_tag on client_company_tag.id = real_estate_object_client_company_tag.client_company_tag_id
  where real_estate_object_client_company_tag.object_instance_id = real_estate_object.id
$$ language sql stable strict;

create function public.create_real_estate_object_client_company_tag(
  real_estate_object_id uuid,
  client_company_tag_id uuid
) returns public.real_estate_object_client_company_tag as $$
  insert into public.real_estate_object_client_company_tag (object_instance_id, client_company_tag_id, created_by)
  values (
    create_real_estate_object_client_company_tag.real_estate_object_id,
    create_real_estate_object_client_company_tag.client_company_tag_id,
    private.current_user_id()
  )
  returning *
$$ language sql volatile strict;

create function public.delete_real_estate_object_client_company_tag(
  real_estate_object_id uuid,
  client_company_tag_id uuid
) returns public.real_estate_object_client_company_tag as $$
  delete from public.real_estate_object_client_company_tag
  where delete_real_estate_object_client_company_tag.real_estate_object_id = real_estate_object_client_company_tag.object_instance_id
  and delete_real_estate_object_client_company_tag.client_company_tag_id = real_estate_object_client_company_tag.client_company_tag_id
  returning *
$$ language sql volatile strict;

create function public.document_real_estate_object_client_company_tags(
  document public.document
) returns setof public.client_company_tag as $$
  select client_company_tag.* from public.real_estate_object_client_company_tag
    inner join public.client_company_tag
    on real_estate_object_client_company_tag.client_company_tag_id = client_company_tag.id
    inner join public.document_real_estate_object
    on document_real_estate_object.object_instance_id = real_estate_object_client_company_tag.object_instance_id
  where document_real_estate_object.document_id = document.id
  order by real_estate_object_client_company_tag.created_at asc
$$ language sql stable strict;
