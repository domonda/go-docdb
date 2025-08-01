create table work.space_user (
    id uuid primary key default uuid_generate_v4(),

    space_id uuid not null references work.space(id)  on delete cascade,
    user_id  uuid not null references public.user(id) on delete cascade,
    unique(space_id, user_id),

    -- Changing "rights" is not be possible after creation. To change: delete and create a new entry.
    rights_id uuid not null references work.rights on delete restrict,

    added_by uuid not null references public.user(id) on delete restrict,
    added_at timestamptz not null default now()
);

-- TODO: insert and delete rights
grant select on work.space_user to domonda_wg_user;
grant select on work.space_user to domonda_user;

create index space_user_space_id_idx on work.space_user (space_id);
create index space_user_user_id_idx on work.space_user (user_id);
create index space_user_rights_id_idx on work.space_user (rights_id);
