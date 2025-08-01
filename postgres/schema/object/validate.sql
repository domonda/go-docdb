create function object.validate_instance(instance_id uuid) returns void
language plpgsql volatile as $$
declare
    inst          object.instance;
    cls           object.class;
    cprop         object.class_prop;
    array_indices int[];
    array_index   int;
    array_len     int;
    option_index  int;
    -- command       text;
begin
    select * into inst from object.instance where id = instance_id;
    if not found then
        raise exception 'object instance %s not found', instance_id;
    end if;

    select * into cls from object.class where name = inst.class_name;

    for cprop in (
        select *
        from object.class_prop
        where class_name = cls.name
        order by pos
    ) loop
        if cprop.type in ('TEXT_OPTION', 'TEXT_OPTION_ARRAY') then
            if cprop.options is null then
                raise exception 'object instance % option class property % has null options', instance_id, cprop.name;
            end if;
            if cardinality(cprop.options) = 0 then
                raise exception 'object instance % option class property % has no options', instance_id, cprop.name;
            end if;

            for option_index in (
                select p.option_index
                from object.text_option_prop as p
                where p.instance_id = validate_instance.instance_id
                    and p.class_prop_id = cprop.id
            ) loop
                if option_index < 0 or option_index >= cardinality(cprop.options) then
                    raise exception 'object instance % option_index % of property % out of bounds [0..%] for options %', instance_id, i, cprop.name, cardinality(cprop.options), cprop.options;
                end if;
            end loop;
        else
            if cprop.options is not null then
                raise exception 'object instance % non option class property % has options', instance_id, cprop.name;
            end if;
        end if;

        -- Collect array_index column values of of prop type table rows
        -- use -1 for null values
        execute format(
            $query$
                select array_agg(coalesce(p.array_index, -1) order by p.array_index)
                from %s as p
                where p.instance_id = $1 and p.class_prop_id = $2
            $query$,
            object.prop_type_table(cprop.type)
        ) into array_indices using validate_instance.instance_id, cprop.id;

        array_len := coalesce(cardinality(array_indices), 0);
        if cprop.required and array_len = 0 then
            raise exception 'object instance % required prop % has no values', instance_id, cprop.name;
        end if;

        if object.prop_type_is_array(cprop.type) then
            for array_index in 0..array_len-1 loop
                if array_indices[array_index+1] = -1 then
                    raise exception 'object instance % array prop % array_index is null at array_indices[%]', instance_id, cprop.name, array_index;
                end if;
                if array_indices[array_index+1] <> array_index then
                    raise exception 'object instance % array prop % array_index not continuous, got array_index % at array_indices[%]', instance_id, cprop.name, array_indices[array_index+1], array_index;
                end if;
            end loop;
        else
            if array_len < 0 or array_len > 1 then
                raise exception 'object instance % non array prop % must have 0 or 1 values but has %', instance_id, cprop.name, array_len;
            end if;
            if array_len = 1 and array_indices[1] <> -1 then
                raise exception 'object instance % non array prop % array_index must be null but is %', instance_id, cprop.name, array_indices[1];
            end if;
        end if;
    end loop;

    return;
end
$$;
