create table private.abacus_client_sync (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    started_by text not null check(length(started_by) > 0),
    started_at timestamptz not null default now(),
    ended_at   timestamptz,
    -- ended_with_error can only be set together with ended_at
    ended_with_error text check(length(ended_with_error) > 0 and (ended_with_error is null or ended_at is not null))
);