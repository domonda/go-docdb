create view api.real_estate_object as (
  select
    o.id,
    o.client_company_id,
    o.type::text,
    o.number,
    o.accounting_area,
    o.user_account,
    o.note,
    o.address,
    o.alternative_addresses,
    o.zip,
    o.city,
    o.country,
    o.iban,
    o.bic,
    o.active,
    public.real_estate_object_title(o) as title
  from public.real_estate_object as o
  where o.client_company_id = api.current_client_company_id()
);

grant select on table api.real_estate_object to domonda_api;

comment on column api.real_estate_object.client_company_id is '@notNull';
comment on column api.real_estate_object.type is '@notNull';
comment on column api.real_estate_object.number is '@notNull';
comment on view api.real_estate_object is $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
A real estate object.$$;

----

create function api.real_estate_object_by_number(object_no text)
returns api.real_estate_object as
$$
    select *
    from api.real_estate_object
    where "number" = object_no
$$
language sql stable strict security definer;

comment on function api.real_estate_object_by_number is '`RealEstateObject` with a given number.';


create function api.document_real_estate_object(doc api.document)
returns api.real_estate_object as
$$
    select o.*
    from api.real_estate_object as o
        join public.document_real_estate_object as d on d.document_id = doc.id
    where o.id = d.object_instance_id
$$
language sql stable strict security definer; -- is ok because the user has to get the document first

comment on function api.document_real_estate_object is 'The `Document`''s assigned `RealEstateObject`.';
