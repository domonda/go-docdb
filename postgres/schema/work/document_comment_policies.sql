-- select

create policy select_document_comment_user_is_super on public.document_comment
  as permissive
  for select
  to domonda_wg_user
  using (
    private.current_user_super()
  );

create policy select_document_comment_user_commented on public.document_comment
  as permissive
  for select
  to domonda_wg_user
  using (
    private.current_user_id() = document_comment.commented_by
  );

create policy select_document_comment_user_is_mentioned on public.document_comment
  as permissive
  for select
  to domonda_wg_user
  using (
    private.current_user_id() = any(public.document_comment_mentioned_user_ids(document_comment))
  );

-- insert

create function public.can_current_user_comment_on_document(
  document_id uuid
) returns boolean as $$
  select
  -- TODO: domonda_user
  not public.current_user_is_wg()
  -- domonda_wg_user
  or exists (select from work.group_user
      inner join work.rights on rights.id = group_user.rights_id
      inner join work.group_document on group_document.group_id = group_user.group_id
    where group_user.user_id = private.current_user_id()
    and group_document.document_id = document_id
    and rights.can_comment_on_documents)
$$ language sql stable strict;
comment on function public.can_current_user_comment_on_document is
'@notNull';

create function public.document_can_current_user_comment(
  document public.document
) returns boolean as $$
  select public.can_current_user_comment_on_document(document.id)
$$ language sql stable strict;
comment on function public.document_can_current_user_comment is
'@notNull';

create policy insert_document_comment_user_can_comment on public.document_comment
  as permissive
  for insert
  to domonda_wg_user
  with check (
    public.can_current_user_comment_on_document(document_comment.document_id)
  );

----

alter table public.document_comment enable row level security;
