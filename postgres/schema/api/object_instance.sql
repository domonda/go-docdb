create function api.object_instance_props_json(id uuid) returns json
language sql stable strict security definer as
$$
    select object.instance_props_json(instance.id)
    from object.instance
    where client_company_id = api.current_client_company_id()
$$;

create view api.object_instance with (security_barrier) as 
    select
        id,
        client_company_id,
        class_name,
        created_by,
        created_at,
        disabled_by,
        disabled_at,
        disabled_at is null as active,
        api.object_instance_props_json(id) as props_json
    from object.instance
    where client_company_id = api.current_client_company_id();

grant select on table api.object_instance to domonda_api;

comment on column api.object_instance.client_company_id is '@notNull';
comment on column api.object_instance.class_name is '@notNull';
comment on column api.object_instance.created_by is '@notNull';
comment on column api.object_instance.created_at is '@notNull';
comment on column api.object_instance.active is '@notNull';
comment on column api.object_instance.props_json is '@notNull';
comment on view api.object_instance is $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
$$;


create function api.object_instances_by_class_name(class_name text) returns setof api.object_instance
language sql stable strict as
$$
    select *
    from api.object_instance
    where object_instance.class_name = object_instances_by_class_name.class_name
$$;
