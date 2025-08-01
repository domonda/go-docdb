create table object.text_prop (
    id uuid primary key default uuid_generate_v4(),

    instance_id   uuid not null references object.instance(id) on delete cascade,
    class_prop_id uuid not null references object.class_prop(id) on delete restrict,

    array_index int check(array_index >= 0), -- zero based
    constraint text_prop_unique_array_index unique (instance_id, class_prop_id, array_index),

    value trimmed_text not null, -- Non empty text without leading or trailing whitespace. TODO: should we allow empty strings?

    updated_by trimmed_text not null,
    updated_at timestamptz  not null default now(),
    created_by trimmed_text not null,
    created_at timestamptz  not null default now()
);

grant all on object.text_prop to domonda_user;
grant select on object.text_prop to domonda_wg_user;

create index text_prop_instance_id_idx on object.text_prop (instance_id);
create index text_prop_class_prop_id_idx on object.text_prop (class_prop_id);
create index text_prop_instance_id_class_prop_id_idx on object.text_prop (instance_id, class_prop_id);


----

create function object.update_text_prop(
    instance_id uuid,
    prop_name   text,
    value       text = null,
    updated_by  trimmed_text = private.current_user_id()::trimmed_text
) returns object.text_prop
language plpgsql volatile as
$$
declare
    class_prop   object.class_prop;
    updated_prop object.text_prop;
    command      text;
begin
    value := nullif(trim(value), ''); -- Empty string is not allowed, use null instead
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'TEXT');

    begin
        command := object.query_for_update_prop('object.text_prop', instance_id, class_prop, value is null);
        execute command into updated_prop using value, updated_by;
    exception when others then
        raise exception E'%\nfrom object.query_for_update_prop:%', sqlerrm, command;
    end;
    
    return updated_prop;
end
$$;

grant execute on function object.update_text_prop to domonda_user;

----

create function object.update_text_array_prop(
    instance_id uuid,
    prop_name   text,
    "values"    text[],
    updated_by  trimmed_text = private.current_user_id()::trimmed_text
) returns setof object.text_prop
language plpgsql volatile as $$
declare
    class_prop object.class_prop;
    array_len  int;
    command    text;
begin
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'TEXT_ARRAY');
    array_len  := coalesce(cardinality("values"), 0);

    begin
        for array_index in 0..array_len-1 loop
            command := object.query_for_update_prop_array_elem('object.text_prop');
            execute command using instance_id, class_prop.id, array_index, "values"[array_index+1], updated_by;
        end loop;
    exception when others then
        raise exception E'%\nfrom object.query_for_update_prop_array_elem:%', sqlerrm, command;
    end;

    command := object.query_for_trimmed_prop_array('object.text_prop');
    -- raise notice E'command: %\n%, %, %', command, instance_id, class_prop.id, array_len;
    return query
        execute command using instance_id, class_prop.id, array_len;
end
$$;

grant execute on function object.update_text_array_prop to domonda_user;

----

-- create function object.get_text_prop_value(instance_id uuid, prop_name text) returns text
-- language sql stable as
-- $$
--   select coalesce(
--     (
--       select value
--       from object.text_prop
--       where text_prop.instance_id = get_text_prop_value.instance_id
--       and exists (
--         select from object.class_prop
--         where class_prop.id = text_prop.class_prop_id
--         and class_prop.name = get_text_prop_value.prop_name
--       )
--     ),
--     (
--       -- Return empty string as default value if text_prop does not exist
--       -- but the instance and the named class prop exists
--       select ''
--       from object.instance
--       where instance.id = get_text_prop_value.instance_id
--       and exists (
--         select from object.class_prop
--         where class_prop.class_name = instance.class_name
--         and class_prop.name = get_text_prop_value.prop_name
--       )
--     )
--   )
-- $$;