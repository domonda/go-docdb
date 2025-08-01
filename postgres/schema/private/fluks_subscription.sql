create table private.fluks_subscription (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

	trigger_id      text not null,
	tenant_id       text not null,
	subscription_id text not null,
    unique(trigger_id, tenant_id, subscription_id),

	created_at timestamptz not null default now()
);

create index on private.fluks_subscription(client_company_id);