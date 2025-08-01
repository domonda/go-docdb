create type abacus.sys as enum (
    'DATEV', -- API: 1
    'BMD',   -- API: 2
    'RZL'    -- API: 4
);

create table abacus.company (
    id                                   uuid primary key,
    accounting_company_client_company_id uuid not null references public.accounting_company(client_company_id) on delete cascade,

    sys abacus.sys not null,

    updated_at updated_time not null,
    created_at created_time not null
);

create index abacus_company_accounting_company_client_company_id_idx on abacus.company(accounting_company_client_company_id);