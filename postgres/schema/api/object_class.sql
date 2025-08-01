-- create view api.object_class with (security_barrier) as 
--     select
--         name,
--         client_company_id
--     from object.class
--     where client_company_id is null
--         or client_company_id = api.current_client_company_id();

-- grant select on table api.object_class to domonda_api;

-- comment on column api.object_class.name is '@notNull';
-- comment on column api.object_class.client_company_id is '@notNull';
-- comment on view api.object_class is $$
-- @primaryKey name
-- @foreignKey (client_company_id) references api.client_company (company_id)
-- $$;


create view api.object_class_prop as
    select
        id,
        class_name,
        name,
        "type",
        required,
        options,
        description,
        pos
    from object.class_prop;

grant select on table api.object_class_prop to domonda_api;

comment on column api.object_class_prop.id         is '@notNull';
comment on column api.object_class_prop.class_name is '@notNull';
comment on column api.object_class_prop.name       is '@notNull';
comment on column api.object_class_prop.type       is '@notNull';
comment on column api.object_class_prop.required   is '@notNull';
comment on column api.object_class_prop.pos        is '@notNull';
comment on view   api.object_class_prop is '@primaryKey id';


create function api.object_class_props(class_name text) returns setof api.object_class_prop
language sql stable strict as
$$
    select *
    from api.object_class_prop
    where object_class_prop.class_name = object_class_props.class_name
    order by pos
$$;