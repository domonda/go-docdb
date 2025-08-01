create view public.signa_company_accounting_format as (
  select
    "option"   as "accounting_format",
    null::text as "description"
  from object.class_prop,
    unnest(class_prop.options) as "option"
  where "class_name" = 'SignaCompany'
    and "name" = 'BUHA-Format'
);

comment on view public.signa_company_accounting_format is $$
@enum
@primaryKey accounting_format
$$;

grant select on table public.signa_company_accounting_format to domonda_user;
grant select on table public.signa_company_accounting_format to domonda_wg_user;

create domain public.signa_company_accounting_format_enum_domain as text;

----

create view public.signa_company as (
  select
    instance.id,
    instance.client_company_id,
    instance.created_at,
    instance.created_by,
    instance.disabled_at,
    instance.disabled_by,
    instance.disabled_at is null as "active",
    (
      select text_prop.value
      from object.text_prop
        inner join object.class_prop
        on class_prop.id = text_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'ID im Signa-System'
      where text_prop.instance_id = instance.id
    ) as "signa_id",
    (
      select text_prop.value
      from object.text_prop
        inner join object.class_prop
        on class_prop.id = text_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Firmenname'
      where text_prop.instance_id = instance.id
    ) as "company_name",
    (
      select vat_id_prop.value
      from object.vat_id_prop
        inner join object.class_prop
        on class_prop.id = vat_id_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'UID Nummer'
      where vat_id_prop.instance_id = instance.id
    ) as "vat_id",
    (
      select email_address_prop.value
      from object.email_address_prop
        inner join object.class_prop
        on class_prop.id = email_address_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Email'
      where email_address_prop.instance_id = instance.id
    ) as "email",
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
        and class_prop.name = 'Andere Namen und Adressen'
      where text_prop.instance_id = instance.id
    ) as "alternative_names_and_addresses",
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
      select class_prop.options[text_option_prop.option_index+1]::signa_company_accounting_format_enum_domain
      from object.text_option_prop
        inner join object.class_prop
        on class_prop.id = text_option_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'BUHA-Format'
      where text_option_prop.instance_id = instance.id
    ) as "accounting_format",
    (
      select array_agg(email_address_prop.value)
      from object.email_address_prop
        inner join object.class_prop
        on class_prop.id = email_address_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Prüfer'
      where email_address_prop.instance_id = instance.id
    ) as "controller",
    (
      select array_agg(email_address_prop.value)
      from object.email_address_prop
        inner join object.class_prop
        on class_prop.id = email_address_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Prüfer 2'
      where email_address_prop.instance_id = instance.id
    ) as "controller_two",
    (
      select array_agg(email_address_prop.value)
      from object.email_address_prop
        inner join object.class_prop
        on class_prop.id = email_address_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Freigeber'
      where email_address_prop.instance_id = instance.id
    ) as "approver",
    (
      select array_agg(email_address_prop.value)
      from object.email_address_prop
        inner join object.class_prop
        on class_prop.id = email_address_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Freigeber 2'
      where email_address_prop.instance_id = instance.id
    ) as "approver_two",
    (
      select array_agg(email_address_prop.value)
      from object.email_address_prop
        inner join object.class_prop
        on class_prop.id = email_address_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Clearingstelle'
      where email_address_prop.instance_id = instance.id
    ) as "clearing",
    (
      select array_agg(email_address_prop.value)
      from object.email_address_prop
        inner join object.class_prop
        on class_prop.id = email_address_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Buchhalter'
      where email_address_prop.instance_id = instance.id
    ) as "accountant",
    (
      select array_agg(email_address_prop.value)
      from object.email_address_prop
        inner join object.class_prop
        on class_prop.id = email_address_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Einsichtsberechtigte'
      where email_address_prop.instance_id = instance.id
    ) as "read_only",
    (
      select array_agg(email_address_prop.value)
      from object.email_address_prop
        inner join object.class_prop
        on class_prop.id = email_address_prop.class_prop_id
        and class_prop.class_name = class.name
        and class_prop.name = 'Ablehnung Emailliste'
      where email_address_prop.instance_id = instance.id
    ) as "rejected"
  from object.instance
    inner join object.class on class.name = 'SignaCompany'
  where instance.class_name = class.name
);

comment on column public.signa_company.id is '@notNull';
comment on column public.signa_company.client_company_id is '@notNull';
comment on column public.signa_company.created_at is '@notNull';
comment on column public.signa_company.created_by is '@notNull';
comment on column public.signa_company.signa_id is '@notNull';
comment on column public.signa_company.company_name is '@notNull';
comment on column public.signa_company.address is '@notNull';
comment on column public.signa_company.zip is '@notNull';
comment on column public.signa_company.city is '@notNull';
comment on column public.signa_company.country is '@notNull';
comment on column public.signa_company.accounting_format is '@notNull';
comment on view public.signa_company is $$
@primaryKey id
@foreignKey (client_company_id) references public.client_company (company_id)
@foreignKey (accounting_format) references public.signa_company_accounting_format (accounting_format)
$$;

grant select on public.signa_company to domonda_user;
grant select on public.signa_company to domonda_wg_user;

----

create function public.document_category_object_instance_signa_company(
  document_category_object_instance public.document_category_object_instance
) returns public.signa_company
language sql stable as $$
  select * from public.signa_company
  where signa_company.id = document_category_object_instance.object_instance_id
$$;

comment on function public.document_category_object_instance_signa_company is '@notNull';

----

create function public.document_signa_company(
  document public.document
) returns public.signa_company
language sql stable as $$
  select public.document_category_object_instance_signa_company(document_category_object_instance)
  from public.document_category_object_instance
  where document_category_object_instance.document_category_id = document.category_id
$$;
