create table work.rights (
    id uuid primary key default uuid_generate_v4(),

    -- TODO: decide to whom do the rights belong (who is the manager/owner)
    -- space_id uuid references work.space(id) on delete cascade,
    -- group_id uuid references work.group(id) on delete cascade,

    -- TODO: uniqueness on name+manager/owner
    name text not null unique,

    can_comment_on_documents boolean not null default false,
    can_change_documents     boolean not null default false,

    -- TODO: add when needed
    -- can_manage_space boolean not null default false,
    -- can_manage_group boolean not null default false,
    -- can_view_banking boolean not null default false,

    updated_by uuid references public.user(id) on delete restrict,
    updated_at timestamptz not null default now(),

    created_by uuid not null references public.user(id) on delete restrict,
    created_at timestamptz not null default now()
);

-- TODO: grant insert and update when work.rights manager/owner problem is solved
grant select on work.rights to domonda_wg_user;
grant select on work.rights to domonda_user;

comment on table work.rights is 'The rights of a user in a work space or a work group. Read rights for documents is the default; meaning, even if all rights are `false`, the user will have read-only access to the documents.';

comment on column work.rights.can_comment_on_documents is 'Can the user leave comments on documents belonging to the group.';
comment on column work.rights.can_change_documents is 'Can the user upload/import a new document version, delete/undelete, change general properties about the document itself - like the category, etc.';

create index work_rights_can_comment_on_documents_idx on work.rights (can_comment_on_documents);
create index work_rights_can_change_documents_idx on work.rights (can_change_documents);
