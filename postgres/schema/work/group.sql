create table work.group (
    id uuid primary key default uuid_generate_v4(),

    -- Object instances can hold props for the users of the group to edit.
    -- Work groups in a way extend objects with collaboration features.
    -- Objects reference a client-company and an object class
    -- which in turn defines the class of the work group.
    object_instance_id uuid not null references object.instance(id) on delete restrict,
    constraint unique_object_per_group unique(object_instance_id),

    title trimmed_text,

    created_by uuid not null references public.user(id) on delete restrict,
    created_at timestamptz not null default now(),

    disabled_by uuid references public.user(id) on delete restrict,
    disabled_at timestamptz,
    constraint disabled_by_at check((disabled_by is null) = (disabled_at is null))
);

grant select on work.group to domonda_user;
grant select on work.group to domonda_wg_user;

create index group_object_instance_id_idx on work.group(object_instance_id);
create index group_disabled_by_idx on work.group(disabled_by);
create index group_disabled_at_idx on work.group(disabled_at);


create function work.create_group(
    client_company_id uuid,
    class_name        text,
    title             text = null,
    created_by        uuid = private.current_user_id()
) returns work.group
language sql volatile as $$
    with obj as (
        insert into object.instance (client_company_id, class_name, created_by)
		values (create_group.client_company_id, create_group.class_name, create_group.created_by::trimmed_text)
        returning *
    )
    insert into work.group (object_instance_id, title, created_by)
    values ((select id from obj), create_group.title, create_group.created_by)
    returning *
$$;
