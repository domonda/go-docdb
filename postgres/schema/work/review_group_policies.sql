---- select

create policy select_review_group_user_is_super on public.review_group
  as permissive
  for select
  to domonda_wg_user
  using (
    private.current_user_super()
  );

create policy select_review_group_user_has_access_to_all_documents_inside on public.review_group
  as permissive
  for select
  to domonda_wg_user
  using (
    -- user can access the review group ONLY if he can access every single document
    not exists (
      select from public.review_group_document
        left join public.document on document.id = review_group_document.source_document_id
      where review_group_document.review_group_id = review_group.id
      and review_group_document.source_document_id is not null
      and document is null
    )
  );

----

alter table public.review_group enable row level security;
