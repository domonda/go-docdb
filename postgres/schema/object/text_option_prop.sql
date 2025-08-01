create table object.text_option_prop (
    id uuid primary key default uuid_generate_v4(),

    instance_id   uuid not null references object.instance(id) on delete cascade,
    class_prop_id uuid not null references object.class_prop(id) on delete restrict,

    array_index  int check(array_index >= 0),           -- zero based
    constraint text_option_prop_unique_array_index unique (instance_id, class_prop_id, array_index),

    option_index int not null check(option_index >= 0), -- zero based array index for object.class_prop(options)

    updated_by trimmed_text not null,
    updated_at timestamptz  not null default now(),
    created_by trimmed_text not null,
    created_at timestamptz  not null default now()
);

grant all on object.text_option_prop to domonda_user;
grant select on object.text_option_prop to domonda_wg_user;

create index text_option_prop_prop_instance_id_idx on object.text_option_prop (instance_id);
create index text_option_prop_class_prop_id_idx on object.text_option_prop (class_prop_id);
create index text_option_prop_instance_id_class_prop_id_idx on object.text_option_prop (instance_id, class_prop_id);

----

create function object.text_option_prop_value(prop object.text_option_prop) returns text
language sql stable strict as $$
    select options[prop.option_index+1]
    from object.class_prop
    where id = prop.class_prop_id
$$;

grant execute on function object.text_option_prop_value to domonda_user;

----

-- Update using option_index
create function object.update_text_option_prop_index(
    instance_id  uuid,
    prop_name    text,
    option_index int = null,
    updated_by   trimmed_text = private.current_user_id()::trimmed_text
) returns object.text_option_prop
language plpgsql volatile as
$$
declare
    class_prop   object.class_prop;
    updated_prop object.text_option_prop;
    command      text;
begin
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'TEXT_OPTION');

    begin
        command := object.query_for_update_prop('object.text_option_prop', instance_id, class_prop, option_index is null, 'option_index');
        execute command into updated_prop using value, updated_by;
    exception when others then
        raise exception E'%\nfrom object.query_for_update_prop:%', sqlerrm, command;
    end;
    
    return updated_prop;
end
$$;

grant execute on function object.update_text_option_prop_index to domonda_user;

----

create function object.update_text_option_array_prop_indices(
    instance_id    uuid,
    prop_name      text,
    option_indices int[] = null,
    updated_by     trimmed_text = private.current_user_id()::trimmed_text
) returns setof object.text_option_prop
language plpgsql volatile as $$
declare
    class_prop object.class_prop;
    array_len  int;
    command    text;
begin
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'TEXT_OPTION_ARRAY');
    array_len  := coalesce(cardinality(option_indices), 0);

    begin
        for array_index in 0..array_len-1 loop
            command := object.query_for_update_prop_array_elem('object.text_option_prop');
            execute command using instance_id, class_prop.id, array_index, option_indices[array_index+1], updated_by;
        end loop;
    exception when others then
        raise exception E'%\nfrom object.query_for_update_prop_array_elem:%', sqlerrm, command;
    end;

    command := object.query_for_trimmed_prop_array('object.text_option_prop');
    return query
        execute command using instance_id, class_prop.id, array_len;
end
$$;

grant execute on function object.update_text_option_array_prop_indices to domonda_user;

----

-- Update using option_text
create function object.update_text_option_prop(
    instance_id  uuid,
    prop_name    text,
    option_text  text = null,
    updated_by   trimmed_text = private.current_user_id()::trimmed_text
) returns object.text_option_prop
language plpgsql volatile as
$$
declare
    class_prop   object.class_prop;
    updated_prop object.text_option_prop;
    option_index int;
    command      text;
begin
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'TEXT_OPTION');
    if option_text is not null then
        option_index := array_position(class_prop.options, option_text)-1; -- zero based
        if option_index is null then
            raise exception 'option_text % not found in options %', option_texts[array_index+1], class_prop.options;
        end if;
    end if;

    begin
        command := object.query_for_update_prop('object.text_option_prop', instance_id, class_prop, option_index is null, 'option_index');
        execute command into updated_prop using option_index, updated_by;
    exception when others then
        raise exception E'%\nfrom object.query_for_update_prop:%', sqlerrm, command;
    end;
    
    return updated_prop;
end
$$;

grant execute on function object.update_text_option_prop to domonda_user;

----

create function object.update_text_option_array_prop(
    instance_id  uuid,
    prop_name    text,
    option_texts text[] = null,
    updated_by   trimmed_text = private.current_user_id()::trimmed_text
) returns setof object.text_option_prop
language plpgsql volatile as $$
declare
    class_prop   object.class_prop;
    array_len    int;
    option_index int;
    command      text;
begin
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'TEXT_OPTION_ARRAY');
    array_len  := coalesce(cardinality(option_texts), 0);

    begin
        for array_index in 0..array_len-1 loop
            option_index := array_position(class_prop.options, option_texts[array_index+1])-1; -- zero based
            if option_index is null then
                raise exception 'option_text % not found in options %', option_texts[array_index+1], class_prop.options;
            end if;
            command := object.query_for_update_prop_array_elem('object.text_option_prop', 'option_index');
            execute command using instance_id, class_prop.id, array_index, option_index, updated_by;
        end loop;
    exception when others then
        raise exception E'%\nfrom object.query_for_update_prop_array_elem:%', sqlerrm, command;
    end;

    command := object.query_for_trimmed_prop_array('object.text_option_prop');
    return query
        execute command using instance_id, class_prop.id, array_len;
end
$$;

grant execute on function object.update_text_option_array_prop to domonda_user;
