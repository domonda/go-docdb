create table private.blocked_api_key (
    id uuid primary key default uuid_generate_v4(),

    api_key           text not null,
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    blocked_at timestamptz not null default now(),
    blocked_by uuid references public.user(id) on delete set null,
    reason     text not null check(length(trim(reason)) > 0)
);

create unique index blocked_api_key_api_key_idx on private.blocked_api_key(api_key);