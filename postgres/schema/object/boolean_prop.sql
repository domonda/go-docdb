create table object.boolean_prop (
  id uuid primary key default uuid_generate_v4(),

  instance_id   uuid not null references object.instance(id) on delete cascade,
  class_prop_id uuid not null references object.class_prop(id) on delete restrict,

  array_index int check(array_index >= 0), -- zero based
  constraint boolean_prop_unique_array_index unique (instance_id, class_prop_id, array_index),

  value boolean not null,

  updated_by trimmed_text not null,
  updated_at timestamptz  not null default now(),
  created_by trimmed_text not null,
  created_at timestamptz  not null default now()
);

grant all on object.boolean_prop to domonda_user;
grant select on object.boolean_prop to domonda_wg_user;

create index boolean_prop_instance_id_idx on object.boolean_prop (instance_id);
create index boolean_prop_class_prop_id_idx on object.boolean_prop (class_prop_id);
create index boolean_prop_instance_id_class_prop_id_idx on object.boolean_prop (instance_id, class_prop_id);

----

create function object.update_boolean_prop(
    instance_id uuid,
    prop_name   text,
    value       boolean = null,
    updated_by  trimmed_text = private.current_user_id()::trimmed_text
) returns object.boolean_prop
language plpgsql volatile as
$$
declare
    class_prop   object.class_prop;
    command      text;
    updated_prop object.boolean_prop;
begin
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'BOOLEAN');
    command := object.query_for_update_prop('object.boolean_prop', instance_id, class_prop, value is null);
    execute command into updated_prop using value, updated_by;
    return updated_prop;
end
$$;

grant execute on function object.update_boolean_prop to domonda_user;

----

create function object.update_boolean_array_prop(
    instance_id uuid,
    prop_name   text,
    "values"    boolean[],
    updated_by  trimmed_text = private.current_user_id()::trimmed_text
) returns setof object.boolean_prop
language plpgsql volatile as $$
declare
    class_prop object.class_prop;
    array_len  int;
    command    text;
begin
    class_prop := object.get_instance_class_prop_and_check(instance_id, prop_name, 'BOOLEAN_ARRAY');
    array_len  := coalesce(cardinality("values"), 0);
    for array_index in 0..array_len-1 loop
        command := object.query_for_update_prop_array_elem('object.boolean_prop');
        execute command using instance_id, class_prop.id, array_index, "values"[array_index+1], updated_by;
    end loop;
    command := object.query_for_trimmed_prop_array('object.boolean_prop');
    return query
        execute command using instance_id, class_prop.id, array_len;
end
$$;

grant execute on function object.update_boolean_array_prop to domonda_user;
