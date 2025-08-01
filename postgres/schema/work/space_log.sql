create type work.space_log_type as enum (
    'SPACE_CREATED',
    'SPACE_DISABLED',
    'USER_ADDED',
    'USER_REMOVED'
);

create table work.space_log (
    id uuid primary key default uuid_generate_v4(),

    space_id uuid not null references work.space(id) on delete cascade,
    "type"   work.space_log_type not null,
    payload  jsonb,

    created_by uuid references public.user(id) on delete set null,
    created_at timestamptz not null default now()
);