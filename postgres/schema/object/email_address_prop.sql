create table object.email_address_prop (
    id uuid primary key default uuid_generate_v4(),

    instance_id   uuid not null references object.instance(id) on delete cascade,
    class_prop_id uuid not null references object.class_prop(id) on delete restrict,

    array_index int check(array_index >= 0), -- zero based
    constraint email_address_prop_unique_array_index unique (instance_id, class_prop_id, array_index),

    value public.email_addr not null,

    updated_by trimmed_text not null,
    updated_at timestamptz  not null default now(),
    created_by trimmed_text not null,
    created_at timestamptz  not null default now()
);

grant all on object.email_address_prop to domonda_user;
grant select on object.email_address_prop to domonda_wg_user;

create index email_address_prop_prop_instance_id_idx on object.email_address_prop (instance_id);
create index email_address_prop_class_prop_id_idx on object.email_address_prop (class_prop_id);
create index email_address_prop_instance_id_class_prop_id_idx on object.email_address_prop (instance_id, class_prop_id);

----

create function object.update_email_address_prop(
    instance_id uuid,
    prop_name   text,
    value       public.email_addr = null,
    updated_by  trimmed_text = private.current_user_id()::trimmed_text
) returns object.email_address_prop
language plpgsql volatile as
$$
declare
    class_prop   object.class_prop;
    command      text;
    updated_prop object.email_address_prop;
begin
    value := nullif(trim(value::text), ''); -- Empty string is not allowed, use null instead
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'EMAIL_ADDRESS');
    command := object.query_for_update_prop('object.email_address_prop', instance_id, class_prop, value is null);
    execute command into updated_prop using value, updated_by;
    return updated_prop;
end
$$;

grant execute on function object.update_email_address_prop to domonda_user;

----

create function object.update_email_address_array_prop(
    instance_id uuid,
    prop_name   text,
    "values"    public.email_addr[],
    updated_by  trimmed_text = private.current_user_id()::trimmed_text
) returns setof object.email_address_prop
language plpgsql volatile as $$
declare
    class_prop object.class_prop;
    array_len  int;
    command    text;
begin
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'EMAIL_ADDRESS_ARRAY');
    array_len  := coalesce(cardinality("values"), 0);
    for array_index in 0..array_len-1 loop
        command := object.query_for_update_prop_array_elem('object.email_address_prop');
        execute command using instance_id, class_prop.id, array_index, "values"[array_index+1], updated_by;
    end loop;
    command := object.query_for_trimmed_prop_array('object.email_address_prop');
    return query
        execute command using instance_id, class_prop.id, array_len;
end
$$;

grant execute on function object.update_email_address_array_prop to domonda_user;
