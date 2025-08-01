---- select

create policy select_user_all on public.user
  as permissive
  for select
  to domonda_wg_user
  using (true); -- TODO: why not?

create policy select_user_is_super on public.user
  as permissive
  for update
  to domonda_wg_user
  using (
    private.current_user_super()
  );

create policy select_user_is_self on public.user
  as permissive
  for update
  to domonda_wg_user
  using (
    "user".id = (select private.current_user_id())
  );

----

alter table public.user enable row level security;
