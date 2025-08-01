create type work.group_log_type as enum (
    'GROUP_CREATED',
    'GROUP_DISABLED',
    'USER_ADDED',
    'USER_REMOVED'
);

create table work.group_log (
    id uuid primary key default uuid_generate_v4(),

    group_id uuid not null references work.group(id) on delete cascade,
    "type"   work.group_log_type not null,
    payload  jsonb,

    created_by uuid not null references public.user(id) on delete restrict,
    created_at timestamptz not null default now()
);