create type private.sync_api as enum (
    'ABACUS', -- deprecated
    'BLUDELTA',
    'BILLOMAT',
    'FASTBILL',
    'GETMYINVOICES',
    'FINTECHSYSTEMS'
);

create table private.client_company_api_sync (
    id                uuid primary key default uuid_generate_v4(),
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    api         private.sync_api not null,
    api_version text not null check(length(trim(api_version)) > 0),
    sync_reason text not null check(length(trim(sync_reason)) > 0),

    started_by uuid not null references public.user(id) on delete restrict,
	started_at timestamptz not null default now(),
    stopped_at timestamptz,
    constraint stopped_after_started check(stopped_at > started_at),

    error_message text check(length(trim(error_message)) > 0)
);

create unique index private_client_company_api_sync_unique
    on private.client_company_api_sync(client_company_id, api)
    where stopped_at is null;

create index private_client_company_api_sync_idx
    on private.client_company_api_sync(client_company_id, api);