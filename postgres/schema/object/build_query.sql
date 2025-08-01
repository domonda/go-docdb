-- The returned query expects the following parameters: $1=value, $2=updated_by
create function object.query_for_update_prop(
    table_name    text,
    instance_id   uuid,
    class_prop    object.class_prop,
    value_is_null boolean,
    update_column text = 'value'
) returns text
language plpgsql immutable as $$
begin
    if value_is_null then
        if class_prop.required then
            raise exception 'can''t delete required prop "%" for instance %', class_prop.name, instance_id;
        end if;

        return format(
            $query$
                delete from %1$s
                where instance_id = %2$L and class_prop_id = %3$L
                returning *
            $query$,
            table_name,    -- %1$s
            instance_id,   -- %2$L
            class_prop.id  -- %3$L
        );
    end if;

    return format(
        $query$
            with upd as (
                update %1$s
                set %4$I=$1, updated_by=$2, updated_at=now()
                where instance_id = %2$L and class_prop_id = %3$L
                returning id
            ), ins as (
                insert into %1$s (instance_id, class_prop_id, %4$I, updated_by, created_by)
                select %2$L, %3$L, $1, $2, $2
                where not exists (select id from upd)
                returning id
            )
            select * from %1$s
            where id = coalesce((select id from upd), (select id from ins))
        $query$,
        table_name,    -- %1$s
        instance_id,   -- %2$L
        class_prop.id, -- %3$L
        update_column  -- %4$I
    );
end
$$;

----

-- The returned query expects the following parameters: $1=value0, $2=value1, $3=value2, $4=value3, $5=updated_by
create function object.query_for_update_prop_4values(
    table_name     text,
    instance_id    uuid,
    class_prop     object.class_prop,
    value_is_null  boolean,
    update_column0 text,
    update_column1 text,
    update_column2 text,
    update_column3 text
) returns text
language plpgsql immutable as $$
begin
    if value_is_null then
        if class_prop.required then
            raise exception 'can''t delete required prop "%" for instance %', class_prop.name, instance_id;
        end if;

        return format(
            $query$
                delete from %1$s
                where instance_id = %2$L and class_prop_id = %3$L
                returning *
            $query$,
            table_name,    -- %1$s
            instance_id,   -- %2$L
            class_prop.id  -- %3$L
        );
    end if;

    return format(
        $query$
            with upd as (
                update %1$s
                set %4$I=$1, %5$I=$2, %6$I=$3, %7$I=$4, updated_by=$5, updated_at=now()
                where instance_id = %2$L and class_prop_id = %3$L
                returning id
            ), ins as (
                insert into %1$s (instance_id, class_prop_id, %4$I, %5$I, %6$I, %7$I, updated_by, created_by)
                select %2$L, %3$L, $1, $2, $3, $4, $5, $5
                where not exists (select id from upd)
                returning id
            )
            select * from %1$s
            where id = coalesce((select id from upd), (select id from ins))
        $query$,
        table_name,      -- %1$s
        instance_id,     -- %2$L
        class_prop.id,   -- %3$L
        update_column0,  -- %4$I
        update_column1,  -- %5$I
        update_column2,  -- %6$I
        update_column3   -- %7$I
    );
end
$$;

----

-- query where the the following parameters have to be provided:
-- $1=instance_id, $2=class_prop_id, $3=array_index, $4=value, $5=updated_by
create function object.query_for_update_prop_array_elem(
    table_name    text,
    update_column text = 'value'
) returns text
language sql immutable as $$
    select format(
        $query$
            with upd as (
                update %1$s
                set %2$I=$4, updated_by=$5, updated_at=now()
                where instance_id = $1 and class_prop_id = $2 and array_index = $3
                returning id
            ), ins as (
                insert into %1$s (instance_id, class_prop_id, array_index, %2$I, updated_by, created_by)
                select $1, $2, $3, $4, $5, $5
                where not exists (select id from upd)
                returning id
            )
            select * from %1$s
            where id = coalesce((select id from upd), (select id from ins))
        $query$,
        table_name,   -- %1$s
        update_column -- %2$I
    )
$$;


-- query where the the following parameters have to be provided:
-- $1=instance_id, $2=class_prop_id, $3=array_len
create function object.query_for_trimmed_prop_array(
    table_name text
) returns text
language sql immutable as $$
    select format(
        $query$
            with deleted as (
                delete from %1$s
                where instance_id = $1
                    and class_prop_id = $2
                    and array_index >= $3
                returning id
            )
            select p.*
            from %1$s as p, deleted
            where p.instance_id = $1
                and p.class_prop_id = $2
                and not exists (select from deleted where deleted.id = p.id)
        $query$,
        table_name -- %1$s
    )
$$;