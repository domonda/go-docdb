create table work.space (
    id uuid primary key default uuid_generate_v4(),

    -- Object instances can hold props for the users of the space to edit.
    -- Work spaces in a way extend objects with collaboration features.
    -- Objects reference a client-company and an object class
    -- which in turn defines the class of the work space.
    object_instance_id uuid not null references object.instance(id) on delete restrict,
    constraint unique_object_per_space unique(object_instance_id),

    title trimmed_text,

    created_by uuid not null references public.user(id) on delete restrict,
    created_at timestamptz not null default now(),

    disabled_by uuid references public.user(id) on delete restrict,
    disabled_at timestamptz,
    constraint disabled_by_at check((disabled_by is null) = (disabled_at is null))
);

grant select on work.space to domonda_user;
grant select on work.space to domonda_wg_user;

create index space_object_instance_id_idx on work.space(object_instance_id);
create index space_disabled_by_idx on work.space(disabled_by);
create index space_disabled_at_idx on work.space(disabled_at);

----

-- groups can be in multiple spaces
create table work.space_group (
    space_id uuid not null references work.space(id) on delete cascade,
    group_id uuid not null references work.group(id) on delete cascade,
    primary key(space_id, group_id),

    added_by uuid not null references public.user(id) on delete restrict,
    added_at timestamptz not null default now()
);


create function work.create_space(
    client_company_id uuid,
    class_name        text,
    title             text = null,
    created_by        uuid = private.current_user_id()
) returns work.space
language sql volatile as $$
    with obj as (
        insert into object.instance (client_company_id, class_name, created_by)
		values (create_space.client_company_id, create_space.class_name, create_space.created_by::trimmed_text)
        returning *
    )
    insert into work.space (object_instance_id, title, created_by)
    values ((select id from obj), create_space.title, create_space.created_by)
    returning *
$$;