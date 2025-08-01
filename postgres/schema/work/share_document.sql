create function public.document_belonging_work_group_users(
  document public.document
) returns setof work.group_user as $$
  select group_user.*
  from work.group_user
    inner join work.group_document on group_document.group_id = group_user.group_id
  where group_document.document_id = document.id
  order by group_user.added_at desc -- newest on top
$$ language sql stable strict;

create function public.document_shared_with(
  document public.document
) returns setof public.user as $$
  select "user".*
  from public.document_belonging_work_group_users(document) as wg_user
    inner join public.user on "user".id = wg_user.user_id
$$ language sql stable strict;
