create table public.bank (
    bic        bank_bic not null primary key,

    legal_name text not null check(length(legal_name) > 3),
    brand_name text,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select on table public.bank to domonda_user;
grant select on public.bank to domonda_wg_user;

----

create function public.add_bank(
    bic        bank_bic,
    legal_name text,
    brand_name text = null
) returns public.bank as
$$
    insert into public.bank (bic, legal_name, brand_name)
    values (add_bank.bic, add_bank.legal_name, add_bank.brand_name)
    returning *
$$
language sql volatile;

----

create function public.bank_name_by_bic(
    bic public.bank_bic
) returns text as $$
    select coalesce(brand_name, legal_name)
    from public.bank
    where bank.bic = bank_name_by_bic.bic
$$ language sql stable strict;
