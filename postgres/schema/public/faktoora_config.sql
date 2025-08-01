create table public.faktoora_config (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    user_id           uuid not null references public.user(id) on delete cascade,

    token non_empty_text not null,

    updated_at updated_time not null,
	created_at created_time not null
);

create index faktoora_config_client_company_id_idx on public.faktoora_config(client_company_id);
create index faktoora_config_user_id_idx on public.faktoora_config(user_id);

create unique index faktoora_config_unique on public.faktoora_config (client_company_id, user_id);

grant select on table public.faktoora_config to domonda_user;
grant select on table public.faktoora_config to domonda_wg_user;

----

create function public.client_company_current_user_faktoora_config(
    client_company public.client_company
) returns public.faktoora_config as $$
    select * from public.faktoora_config
    where client_company_id = client_company.company_id
        and (user_id is null or user_id = (select private.current_user_id()))
        and public.is_client_company_active(client_company_id)
    order by user_id is null asc -- prefer token for specific user_id
    limit 1
$$ language sql stable strict;
