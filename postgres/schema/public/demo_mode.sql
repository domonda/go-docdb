












-- create table public.demo_client_company (
-- 	client_company_id uuid primary key references public.client_company(id) on delete cascade,

--     demo_mode_from  timestamptz not null default now(),
--     demo_mode_until timestamptz check(demo_until > demo_from),
--     updated_at      updated_time not null
-- );

-- grant select table public.demo_client_company to domonda_user;


-- create function public.client_company_demo_mode(
--     cc public.client_company
-- ) returns boolean as
-- $$
--     select exists (
--         select from public.demo_client_company where (
--             client_company_id = cc.company_id
--         ) and (
--             now() >= demo_mode_from
--         ) and (
--             (demo_mode_until is null) or (now() <= demo_mode_until)
--         )
--     )
-- $$
-- language sql stable;

-- comment on function public.client_company_demo_mode(public.client_company) is 'Returns if the client company is in demo mode right now';

-- grant execute on function public.client_company_demo_mode(public.client_company) to domonda_user;