-- TODO: consider work.space_user too

---- select

create policy select_document_user_is_super on public.document
  as permissive
  for select
  to domonda_wg_user
  using (
    private.current_user_super()
  );

create policy select_document_user_belongs_to_work_group on public.document
  as permissive
  for select
  to domonda_wg_user
  using (
    exists (select from work.group
        inner join work.group_document on group_document.group_id = "group".id
        inner join work.group_user on group_user.group_id = "group".id
      where "group".disabled_at is null
      and group_document.document_id = document.id
      and group_user.user_id = (select private.current_user_id()))
  );

---- update

create policy update_document_user_is_super on public.document
  as permissive
  for update
  to domonda_wg_user
  using (
    private.current_user_super()
  );

create function public.document_can_current_user_change(
  document public.document
) returns boolean as $$
begin
  -- checked out document can be checked in by the same user
  if document.checkout_user_id is not null
  and document.checkout_user_id <> private.current_user_id()
  then
    return false;
  end if;

  -- document must be in a ready state
  if not (public.document_state(document) in (
    'CHECKED_OUT', -- allow state because the checkout user is the current user (see above if)
    'READY',
    'IN_RESTRUCTURE_GROUP', -- ready in a review group
    'BOOKING_CANCELED',
    'READY_FOR_BOOKING',
    'BOOKED', -- TODO: is this unsafe? we should have another INVOICE_can_current_user_change which prevents changing invoice data when booked
    'DELETED', 'SUPERSEDED' -- the documents are not locked, could be still changed
  ))
  then
    return false;
  end if;

  if public.current_user_is_wg() then
    return exists (select from work.group
        inner join work.group_document on group_document.group_id = "group".id
        inner join (work.group_user
          inner join work.rights on rights.id = group_user.rights_id)
        on group_user.group_id = "group".id
      where "group".disabled_at is null
      and group_document.document_id = document.id
      and group_user.user_id = (select private.current_user_id())
      and rights.can_change_documents);
  end if;

  -- document mustnt be in a protected workflow step
  -- work group users dont care about protected workflow steps
  if public.document_is_in_protected_workflow_step(document)
  then
    return false;
  end if;

  -- TODO: workflow step pushes are still allowed, but all other editing is not
  -- -- document mustnt be in a prevent edit workflow step
  -- if public.document_is_in_prevent_edit_workflow_step(document)
  -- then
  --   return false;
  -- end if;

  return private.current_user_super()
  or exists (
    select from control.client_company_user
      inner join control.client_company_user_role on client_company_user_role.name = client_company_user.role_name
    where client_company_user.user_id = (select private.current_user_id())
    and client_company_user.client_company_id = document.client_company_id
    and client_company_user_role.update_documents);
end
$$ language plpgsql stable strict;
comment on function public.document_can_current_user_change is
'@notNull';

create policy update_document_user_can_change on public.document
  as permissive
  for update
  to domonda_wg_user, domonda_user -- intentionally domonda_user too
  using (public.document_can_current_user_change(document));

create function public.document_can_current_user_share(
  document public.document
) returns boolean as $$
declare
  state public.document_state;
begin
  state := public.document_state(document);

  -- TODO: should the document be in ready-like state?
  -- if not (state in (
  --   'READY',
  --   'BOOKING_CANCELED',
  --   'READY_FOR_BOOKING'
  -- ))
  -- then
  --   return false;
  -- end if;

  if public.current_user_is_wg() then
    -- TODO
    return false;
  end if;

  return private.current_user_super()
  or exists (
    select from control.client_company_user
    where client_company_user.user_id = (select private.current_user_id())
    and client_company_user.client_company_id = document.client_company_id
    and role_name in ('ADMIN', 'ACCOUNTANT', 'CLIENT', 'DOCUMENTS_ONLY'));
end
$$ language plpgsql stable strict;
comment on function public.document_can_current_user_share is
'@notNull';

----

alter table public.document enable row level security;
