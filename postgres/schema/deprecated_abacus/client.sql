create table abacus.client (
    id                uuid primary key,
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    abacus_company_id uuid not null references abacus.company(id) on delete cascade,

	client_no        text not null check(length(client_no) <= 20),
    account_no_ength int2 not null default 4 check(account_no_ength >= 0),

    updated_at updated_time not null,
    created_at created_time not null
);

create index abacus_client_client_company_id_idx on abacus.client(client_company_id);
create index abacus_client_abacus_company_id_idx on abacus.client(abacus_company_id);

