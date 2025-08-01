create table object.instance (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    class_name trimmed_text not null references object.class(name) on delete restrict,

    disabled_by trimmed_text,
    disabled_at timestamptz,
    constraint disabled_by_and_at_null check((disabled_by is null) = (disabled_at is null)),

    created_by trimmed_text not null,
    created_at timestamptz  not null default now()
);

grant all on object.instance to domonda_user;
grant select on object.instance to domonda_wg_user;

create index instance_client_company_id_idx on object.instance (client_company_id);
create index instance_class_name_idx on object.instance (class_name);
create index instance_disabled_at_idx on object.instance (disabled_at);


create function object.update_instance_active(
    id         uuid,
    active     boolean,
    updated_by trimmed_text
) returns void
language plpgsql volatile as $$
begin
    if active then
        update object.instance
        set disabled_at=null, disabled_by=null
        where instance.id = update_instance_active.id
            and instance.disabled_at is not null;
    else
        update object.instance
        set disabled_at=now(), disabled_by=update_instance_active.updated_by
        where instance.id = update_instance_active.id
            and instance.disabled_at is null;
    end if;
end
$$;


create function object.instance_prop_names(i object.instance)
  returns text[]
language sql stable strict as
$$
  select object.class_prop_names(class)
  from object.class
  where class.name = i.class_name
$$;


create function object.instance_class_props(i object.instance)
  returns setof object.class_prop
language sql stable strict as
$$
  select class_prop.*
  from object.class_prop
  where class_prop.class_name = i.class_name
$$;


create function object.get_instance_class_prop(instance_id uuid, prop_name text)
  returns object.class_prop
language sql stable strict as
$$
  select cp.*
  from object.class_prop as cp
    join object.instance on instance.id = instance_id
  where cp.name = prop_name
    and cp.class_name = instance.class_name
  limit 1
$$;

create function object.get_instance_class_prop_and_check(
    instance_id     uuid,
    prop_name       text,
    check_prop_type object.prop_type
) returns object.class_prop
language plpgsql stable as $$
declare
    class_prop object.class_prop;
begin
    class_prop := object.get_instance_class_prop(instance_id, prop_name);

    if class_prop is null then
        raise exception 'instance % has no class prop %', instance_id, prop_name;
    end if;

    if class_prop.type <> check_prop_type then
        raise exception 'instance % of class % prop % has type % instead of %s', instance_id, class_prop.class_name, prop_name, class_prop.type, check_prop_type;
    end if;

    return class_prop;
end
$$;


create function object.instance_props_json(id uuid) returns json
language plpgsql stable strict as $$
declare
    cp     object.class_prop;
    result text;
begin
    result := '{';

    for cp in
        select class_prop.* from object.class_prop
        join object.instance on instance.id = instance_props_json.id
        where class_prop.class_name = instance.class_name
        order by pos
    loop
        result := result || to_json(cp.name)::text || ':';
        
        case cp.type
        when 'TEXT' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.text_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null'); -- Or return empty string when required but null? case when cp.required then '""' else 'null'
        when 'TEXT_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.text_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'TEXT_OPTION' then
            result := result || coalesce((
                select to_json(cp.options[p.option_index+1])::text
                from object.text_option_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'TEXT_OPTION_ARRAY' then
            result := result || coalesce((
                select json_agg((cp.options[p.option_index+1]) order by p.array_index)::text
                from object.text_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'ACCOUNT_NO' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.account_no_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'ACCOUNT_NO_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.account_no_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'NUMBER' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.number_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'NUMBER_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.number_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'INTEGER' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.integer_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'INTEGER_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.integer_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'BOOLEAN' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.boolean_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'DATE' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.date_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'DATE_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.date_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'DATE_TIME' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.date_time_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'DATE_TIME_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.date_time_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'IBAN' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.iban_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'IBAN_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.iban_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'BIC' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.bic_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'BIC_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.bic_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'VAT_ID' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.vat_id_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'VAT_ID_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.vat_id_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'COUNTRY' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.country_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'COUNTRY_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.country_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'CURRENCY' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.currency_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'CURRENCY_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.currency_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'CURRENCY_AMOUNT' then
            result := result || coalesce((
                select to_json(public.currency_amount_text(p.value))::text
                from object.currency_amount_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'CURRENCY_AMOUNT_ARRAY' then
            result := result || coalesce((
                select json_agg(public.currency_amount_text(p.value) order by p.array_index)::text
                from object.currency_amount_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'EMAIL_ADDRESS' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.email_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'EMAIL_ADDRESS_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.email_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'USER' then
            result := result || coalesce((
                select to_json(p.value)::text
                from object.user_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'USER_ARRAY' then
            result := result || coalesce((
                select json_agg(p.value order by p.array_index)::text
                from object.user_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        when 'BANK_ACCOUNT' then
            result := result || coalesce((
                select object.bank_account_prop_value(p)::text
                from object.bank_account_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), 'null');
        when 'BANK_ACCOUNT_ARRAY' then
            result := result || coalesce((
                select json_agg(object.bank_account_prop_value(p) order by p.array_index)::text
                from object.bank_account_prop as p
                where p.instance_id = instance_props_json.id
                  and p.class_prop_id = cp.id
            ), '[]');
        else
            -- Gracefully return an error message as prop value during development:
            -- result := result || '"Unsupported prop type ' || cp.type || '"';
            raise exception 'unknown prop type %', cp.type; -- should never happen
        end case;

        result := result || ',';
    end loop;

    result := trim(trailing ',' from result) || '}';

    return result::json;
end
$$;

-- Add view in public schema to add to internal GraphQL API.
-- See api.object_instance for external GraphQL API.
create view public.object_instance as 
    select
        id,
        client_company_id,
        class_name,
        created_by,
        created_at,
        disabled_by,
        disabled_at,
        disabled_at is null as active,
        object.instance_props_json(id) as props_json
    from object.instance;

grant select on table public.object_instance to domonda_user;

comment on column public.object_instance.client_company_id is '@notNull';
comment on column public.object_instance.class_name is '@notNull';
comment on column public.object_instance.created_by is '@notNull';
comment on column public.object_instance.created_at is '@notNull';
comment on column public.object_instance.active is '@notNull';
comment on column public.object_instance.props_json is '@notNull';
comment on view public.object_instance is $$
@primaryKey id
@foreignKey (client_company_id) references public.client_company (company_id)
$$;
