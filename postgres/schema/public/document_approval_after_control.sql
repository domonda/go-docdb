create function private.document_approval_request_can_user_cancel(
  document_approval_request public.document_approval_request,
  user_id uuid
) returns boolean as
$$
  select (
    -- user is super-admin
    (select "type" in ('SUPER_ADMIN', 'SYSTEM') from public.user where "user".id = document_approval_request_can_user_cancel.user_id)
    -- user is issuer of a not-denied approval request
    or (document_approval_request.requester_id = document_approval_request_can_user_cancel.user_id
      and not exists (select from public.document_approval
        where document_approval.next_request_id = document_approval_request.id
      )
    )
    -- user is client company admin
    or exists (
      select from control.client_company_user
      where client_company_user.user_id = document_approval_request_can_user_cancel.user_id
      and client_company_user.client_company_id = (select document.client_company_id
        from public.document
        where document.id = document_approval_request.document_id)
      and client_company_user.role_name = 'ADMIN'
    )
  )
$$
language sql stable;

----

create function public.document_approval_request_validate_change() returns trigger as $$
declare
  request  public.document_approval_request;
  releaser public.user;
begin
  request = NEW;

  -- cannot add a new request for same user until the older ones are released
  if (
    request.approver_id is not null
  ) and (
    -- allow updates on same release request
    (TG_OP = 'INSERT') or (OLD.id != request.id)
  ) and (
    exists (
      select 1 from public.document_approval_request as drr
      where (
        drr.approver_id = request.approver_id
      ) and (
        drr.document_id = request.document_id
      ) and (
        not exists (
          select from public.document_approval
          where document_approval.request_id = drr.id
        )
      )
    )
  ) then
    select * into releaser
    from public.user where id = request.approver_id;

    if private.current_user_language() = 'de'
    then raise exception 'Das System kann keinen neue Genehmigungsaufforderung an % (%) stellen, da für den Benutzer bereits ein offener Genehmigungsantrag existiert.', public.user_full_name(releaser), releaser.email;
    end if;

    raise exception 'Cannot issue a new approval request to % (%) because the user already has one open.', public.user_full_name(releaser), releaser.email;
  end if;

  return request;
end;
$$ language plpgsql stable;

create trigger document_approval_request_validate_change
  before insert or update on public.document_approval_request
  for each row execute procedure public.document_approval_request_validate_change();

create function public.document_approval_validate_change() returns trigger as $$
declare
  request_client_company_id uuid;
  request  public.document_approval_request;
  approval public.document_approval;
begin
  approval = NEW;
  select
    * into request
  from public.document_approval_request where id = approval.request_id;
  select
    document.client_company_id into request_client_company_id
  from public.document
  where document.id = request.document_id;

  if approval.canceled
  then
    -- cancellation...
    if private.document_approval_request_can_user_cancel(request, approval.approver_id)
    then
      return approval;
    end if;

    if not public.is_client_company_feature_active(
      request_client_company_id,
      'DOCUMENT_APPROVAL_REJECT_CANCEL'
    )
    then
      raise exception 'User is not allowed to cancel the approval request';
    end if;

    -- if the DOCUMENT_APPROVAL_REJECT_CANCEL feature is active,
    -- validate the change as if it's a rejection
  end if;

  -- approval or rejection (or cancellation)...

  -- the requested approver is the same as the actual approver
  if (request.approver_id is not null)
  and (request.approver_id != approval.approver_id)
  and (approval.approver_id != '08a34dc4-6e9a-4d61-b395-d123005e65d3') -- allow replacing with Unknown user when deleting original user
  then
    raise exception 'Requested approver and the actual approver do not match';
  end if;

  -- approver must belong to the requested user group
  if request.user_group_id is not null
  and not exists (
    select from public.user_group_user
    where user_group_user.user_group_id = request.user_group_id
    and user_group_user.user_id = approval.approver_id
  ) then
    raise exception 'Approver does not belong to the requested user group';
  end if;

  -- blank request approver type must match the client company user role
  if (
    request.approver_id is null
  ) and (
    request.user_group_id is null
  ) and (
    case request.blank_approver_type
      when 'ANYONE' then ( -- anyone except verifiers can approve
        exists (
          select 1 from
            control.client_company_user,
            (select client_company_id from public.document where document.id = request.document_id) as document
          where (
            client_company_user.user_id = approval.approver_id
          ) and (
            client_company_user.client_company_id = document.client_company_id
          ) and (
            client_company_user.role_name = 'VERIFIER'
          )
        )
      )
      when 'ACCOUNTANT' then ( -- only accountants can approve
        not exists (
          select 1 from
            control.client_company_user,
            (select client_company_id from public.document where document.id = request.document_id) as document
          where (
            client_company_user.user_id = approval.approver_id
          ) and (
            client_company_user.client_company_id = document.client_company_id
          ) and (
            client_company_user.role_name = 'ACCOUNTANT'
          )
        )
      )
      when 'VERIFIER' then ( -- only verifiers can approve
        not exists (
          select 1 from
            control.client_company_user,
            (select client_company_id from public.document where document.id = request.document_id) as document
          where (
            client_company_user.user_id = approval.approver_id
          ) and (
            client_company_user.client_company_id = document.client_company_id
          ) and (
            client_company_user.role_name = 'VERIFIER'
          )
        )
      )
      else true -- raise exception
    end
  ) then
    raise exception 'Approver''s type is not allowed to approve this request.';
  end if;

  return approval;
end;
$$ language plpgsql stable;

create trigger document_approval_validate_change
  before insert or update on public.document_approval
  for each row execute procedure public.document_approval_validate_change();

----

create function public.document_open_approval_request_for_current_user(
  document public.document
) returns public.document_approval_request as
$$
declare
  request public.document_approval_request;
begin
  if current_user = 'domonda_wg_user' then
    -- validation trigger should guarantee 1 open request per user
    select * into request
    from public.document_approval_request
    where document_id = document.id
    and public.is_document_approval_request_open(id)
    and document_approval_request.approver_id = (select private.current_user_id())
    order by approver_id nulls last, created_at asc
    limit 1; -- we limit to 1 in case multiple blank requests exist

    return request;
  end if;

  -- validation trigger should guarantee 1 open request per user
  select * into request
  from public.document_approval_request
  where (
    document_id = document.id
  ) and (
    public.is_document_approval_request_open(id)
  ) and (
    (
      -- blank request
      exists (
        select 1 from control.client_company_user as ccu
        where (
          ccu.user_id = (select private.current_user_id())
        ) and (
          ccu.client_company_id = document.client_company_id
        ) and (
          -- anyone except verifier can approve
          (document_approval_request.blank_approver_type = 'ANYONE'
            and ccu.role_name <> 'VERIFIER')
          -- blank approval type must match the role
          or document_approval_request.blank_approver_type::varchar = ccu.role_name
        ) and (
          -- group approvals cannot be approved by the requester, even if he belongs to the group
          document_approval_request.requester_id <> (select private.current_user_id())
        )
      )
      -- TODO-db-200218 add blank_approver_type check for if the current user can approve
    ) or (
      -- user group request
      document_approval_request.user_group_id in (
        select user_group_user.user_group_id from public.user_group_user
        where user_group_user.user_id = (select private.current_user_id())
      )
    ) or (
      -- direct request
      document_approval_request.approver_id is not distinct from private.current_user_id()
    )
  )
  order by approver_id nulls last, created_at asc
  limit 1; -- we limit to 1 in case multiple blank requests exist

  return request;
end
$$
language plpgsql stable strict;

----

create function public.document_approval_request_can_current_user_approve(
  document_approval_request public.document_approval_request
) returns boolean as
$$
  select (
    public.is_document_approval_request_open(document_approval_request.id)
  ) and (
    (
      -- blank request
      (
         (
          -- client user type matches the blank approver type
          exists (
            select 1 from
              control.client_company_user as ccu,
              (select client_company_id from public.document where id = document_approval_request.document_id) as document
            where (
              ccu.user_id = (select private.current_user_id())
            ) and (
              ccu.client_company_id = document.client_company_id
            ) and (
              -- anyone except verifier can approve
              (document_approval_request.blank_approver_type = 'ANYONE'
                and ccu.role_name <> 'VERIFIER')
              -- blank approval type must match the role
              or document_approval_request.blank_approver_type::varchar = ccu.role_name
            ) and (
              -- group approvals cannot be approved by the requester, even if he belongs to the group
              document_approval_request.requester_id <> (select private.current_user_id())
            )
          )
        ) and (
          -- user has no signed blank requests
          not exists (
            select 1 from public.document_approval as dr
              inner join public.document_approval_request as drr on drr.id = dr.request_id
            where (
              drr.id <> document_approval_request_can_current_user_approve.document_approval_request.id
            ) and (
              drr.document_id = document_approval_request_can_current_user_approve.document_approval_request.document_id
            ) and (
              drr.approver_id is null
            ) and (
              dr.approver_id = (select private.current_user_id())
            )
          )
        )
      )
      -- TODO-db-200218 add blank_approver_type check for if the current user can approve
    ) or (
      -- user group request
      document_approval_request.user_group_id is not null
      and document_approval_request.user_group_id in (
        select user_group_user.user_group_id from public.user_group_user
        where user_group_user.user_id = (select private.current_user_id())
      )
    ) or (
      -- direct request
      document_approval_request.approver_id is not distinct from (select private.current_user_id())
    )
  )
$$ language sql stable strict;
comment on function public.document_approval_request_can_current_user_approve is '@notNull';

create function public.document_approval_request_can_current_user_cancel(
  document_approval_request public.document_approval_request
) returns boolean as $$
  select public.is_document_approval_request_open(document_approval_request.id)
  and private.document_approval_request_can_user_cancel(document_approval_request, private.current_user_id())
$$ language sql stable strict;
comment on function public.document_approval_request_can_current_user_cancel is '@notNull';

----

create function public.document_has_accountant_approval(
  document public.document
) returns boolean as
$$
  select exists (
    select from public.document_approval
      inner join public.document_approval_request on document_approval_request.id = document_approval.request_id
    where document_approval_request.document_id = document.id
    and not document_approval.canceled
    and document_approval.next_request_id is null -- not rejected
    and (
      (document_approval_request.blank_approver_type = 'ACCOUNTANT')
      or
      exists (select from control.client_company_user
      where client_company_user.client_company_id = document.client_company_id
      and client_company_user.user_id = document_approval.approver_id
      and client_company_user.role_name = 'ACCOUNTANT')
    )
  )
$$
language sql stable strict
security definer; -- because of domonda_wg_user (doesnt have access to the `control` schema)

comment on function public.document_has_accountant_approval is '@notNull';
