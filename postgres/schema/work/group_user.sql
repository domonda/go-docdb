create table work.group_user (
    id uuid primary key default uuid_generate_v4(),

    group_id uuid not null references work.group(id)  on delete cascade,
    user_id  uuid not null references public.user(id) on delete cascade,
    unique(group_id, user_id),

    -- Changing "rights" is not be possible after creation. To change: delete and create a new entry.
    rights_id uuid not null references work.rights on delete restrict,

    added_by uuid not null references public.user(id) on delete restrict,
    added_at timestamptz not null default now()
);

-- TODO: insert and delete rights
grant select on work.group_user to domonda_wg_user;
grant select on work.group_user to domonda_user;

create index group_user_group_id_idx on work.group_user (group_id);
create index group_user_user_id_idx on work.group_user (user_id);
create index group_user_rights_id_idx on work.group_user (rights_id);

----

create function work.add_group_user(
    group_id  uuid,
    user_id   uuid,
    added_by  uuid,
    rights_id uuid
) returns work.group_user
language sql volatile as
$$
    insert into work.group_user (
        group_id,
        user_id,
        added_by,
        rights_id
    )
    values (
        add_group_user.group_id,
        add_group_user.user_id,
        add_group_user.added_by,
        add_group_user.rights_id
    )
    returning *
$$;

comment on function work.add_group_user is 'Adds a user to a group';

----

create function work.remove_group_user(
    group_user_id uuid
) returns setof work.group_user
language sql volatile as
$$
    delete from work.group_user
    where group_user_id = remove_group_user.group_user_id
    returning *
$$;

comment on function work.remove_group_user is 'Removes a user from a group';