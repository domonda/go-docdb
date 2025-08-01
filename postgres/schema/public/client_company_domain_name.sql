create table public.email_provider_domain (
    name text primary key
);

grant select on table public.email_provider_domain to domonda_user;

----

create function public.domain_name(addr text) returns text
as $$
    select trim(
        rtrim(
            regexp_replace(
                regexp_replace(
                    regexp_replace(
                        regexp_replace(
                            addr,
                            '^.+://', '', 'g'
                        ),
                        '^www\.', '', 'g'
                    ),
                    '/.*$', '', 'g'
                ),
                '^.+@', '', 'g'
            ),
            '>'
        )
    )
$$ language sql immutable strict;

----

create function public.non_email_provider_domain_name(addr text) returns text
as $$
    with dom as (
        select public.domain_name(addr) as "name"
    )
    select "name" from dom
    where addr not ilike '%-not-valid@airbnb.com%'
    and not exists(
        select from public.email_provider_domain
        where "name" = (select "name" from dom)
    )
$$ language sql immutable strict;

----

create function public.client_company_derived_domain_name(
    cc public.client_company
) returns text as
$$
    select
        coalesce(
            public.domain_name(loc.website),
            public.non_email_provider_domain_name(loc.email),
            (
                with users as (
                    select
                        distinct public.non_email_provider_domain_name(u.email) as dom,
                        count(public.non_email_provider_domain_name(u.email))   as num
                    from public.user as u
                    where u.client_company_id = cc.company_id
                        and u.email is not null
                        and u.type = 'STANDARD'
                        and public.non_email_provider_domain_name(u.email) <> 'domonda.com'
                    group by u.email
                    order by num desc
                    limit 1
                )
                select dom from users
            )
        )
    from public.company_location as loc
    where loc.company_id = cc.company_id and loc.main
$$ language sql immutable strict;

comment on function public.client_company_derived_domain_name is 'Domain name of the `ClientCompany` main `CompanyLocation` website, email, or the most used `User` email address.';
