---- select

create policy select_document_category_user_is_super on public.document_category
  as permissive
  for select
  to domonda_wg_user
  using (
    private.current_user_super()
  );

create policy document_category_user_has_access_to_some_document on public.document_category
  as permissive
  for select
  to domonda_wg_user
  using (
    true -- TODO
  );

----

alter table public.document_category enable row level security;
