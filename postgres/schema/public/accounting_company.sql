create table public.accounting_company (
    client_company_id uuid primary key, -- note: reference to the `public.client_company` is created in `public/client_company.sql`

    is_tax_adviser bool not null default true,
    active         bool not null default true,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select on table public.accounting_company to domonda_user;
grant select on table public.accounting_company to domonda_wg_user; -- TODO: just select I guess?

----

create function public.accounting_company_company_by_client_company_id(
    accounting_company public.accounting_company
) returns public.company as
$$
    select * from public.company where id = accounting_company.client_company_id
$$
language sql stable;

comment on function public.accounting_company_company_by_client_company_id is E'@notNull';
