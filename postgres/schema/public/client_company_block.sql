create table public.client_company_block (
	client_company_id uuid primary key references public.client_company(company_id) on delete cascade,

	starts_at timestamptz not null default now(),
	reason    non_empty_text not null,

	created_at created_time not null
);

comment on column public.client_company_block.starts_at is 'Time at which the block takes effect. If in future, the app should display a countdown alongside the `reason`.';

grant select on public.client_company_block to domonda_user;
grant select on public.client_company_block to domonda_wg_user;

----

create function public.client_company_block_active(
	client_company_block public.client_company_block
) returns boolean as $$
	select client_company_block.starts_at <= now()
$$ language sql stable strict;

comment on function public.client_company_block_active is '@notNull';
