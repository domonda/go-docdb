---- has to either ----

-- be a super admin
create policy review_group_super_admin_policy on public.review_group
  as permissive
  for all
  to domonda_user
  using (private.current_user_super());

-- have a document workflow control entry
create policy review_group_control_exists_policy on public.review_group
  as permissive
  for all
  to domonda_user
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
