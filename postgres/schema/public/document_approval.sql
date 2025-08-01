create type public.document_approval_request_blank_approver_type as enum (
  'ACCOUNTANT',
  'VERIFIER',
  'ANYONE'
  -- once user profiles are implemented
);

create table public.document_approval_request (
  id uuid primary key default uuid_generate_v4(),

  document_id uuid not null references public.document(id) on delete cascade,

  requester_id uuid not null
      default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- system-user ID for unknown user
      references public.user(id) on delete set default,

  approver_id         uuid references public.user(id) on delete set null,
  user_group_id       uuid references public.user_group(id) on delete set null,
  blank_approver_type public.document_approval_request_blank_approver_type, -- deprecated

  constraint only_one_approver_type_allowed check(
    case
      when approver_id is not null
      then user_group_id is null and blank_approver_type is null
      when user_group_id is not null
      then approver_id is null and blank_approver_type is null
      when blank_approver_type is not null
      then approver_id is null and user_group_id is null
      else false
    end
  ),

  message text check(length(message) > 0),

  created_at created_time not null
);

comment on column public.document_approval_request.blank_approver_type is '@deprecated Please use `UserGroup`s instead.';
comment on column public.document_approval_request.message is '@deprecated Please use the `DocumentComment.relatedDocumentApprovalRequest` instead.';

grant select, insert, delete on public.document_approval_request to domonda_user;
grant select on public.document_approval_request to domonda_wg_user;

create index document_approval_request_document_id_idx on public.document_approval_request (document_id);
create index document_approval_request_requester_id_idx on public.document_approval_request (requester_id);
create index document_approval_request_approver_id_idx on public.document_approval_request (approver_id);
create index document_approval_request_user_group_id_idx on public.document_approval_request (user_group_id);
create index document_approval_request_blank_approver_type_idx on public.document_approval_request (blank_approver_type);
create index document_approval_request_created_at_idx on public.document_approval_request (created_at);

----

create table public.document_approval (
  request_id  uuid primary key references public.document_approval_request(id) on delete cascade,
  approver_id uuid not null
      default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- system-user ID for unknown user
      references public.user(id) on delete set default,

  -- to reject an approval, you make another request
  next_request_id uuid references public.document_approval_request(id) on delete cascade,

  -- whether the approval request was simply canceled (not approved and not rejected)
  canceled boolean not null default false,

  constraint approved_rejected_or_canceled check(
    case
      when next_request_id is not null -- rejected
      then not canceled
      when canceled -- canceled
      then next_request_id is null
      else true -- approved
    end
  ),

  id uuid unique not null default uuid_generate_v4(), -- necessary for document_history

  created_at  created_time not null
);

grant select, insert, delete on public.document_approval to domonda_user;
grant select on public.document_approval to domonda_wg_user;

create index document_approval_approver_id_idx on public.document_approval (approver_id);
create index document_approval_next_request_id_idx on public.document_approval (next_request_id);
create index document_approval_canceled_idx on public.document_approval (canceled);
create index document_approval_id_idx on public.document_approval (id);
create index document_approval_created_at_idx on public.document_approval (created_at);

----

create function public.create_document_approval_request_and_reject_workflow(
  document_id         uuid,
  approver_id         uuid = null,
  user_group_id       uuid = null,
  blank_approver_type public.document_approval_request_blank_approver_type = null,
  number_of_requests  integer = null,
  message             jsonb = null
) returns public.document as
$$
declare
  document public.document;
begin
  if (blank_approver_type is not null) then
    perform public.create_blank_document_approval_requests(
      document_id,
      number_of_requests,
      blank_approver_type,
      null -- intentional because transitioning to comments
    );
  else
    perform public.create_document_approval_request(
      document_id,
      approver_id,
      user_group_id,
      null -- intentional because transitioning to comments
    );
  end if;

  return public.set_document_workflow_step_and_comment(
    document_id,
    null,
    message
  );
end;
$$
language plpgsql volatile;

----

create function public.approve_document(
  request_id uuid
) returns public.document_approval as
$$
  insert into public.document_approval (request_id, approver_id)
    values (approve_document.request_id, private.current_user_id())
  returning *
$$
language sql volatile strict;

----

create function public.document_approval_request_approved(
  document_approval_request public.document_approval_request
) returns boolean as
$$
  select exists (
    select from public.document_approval
    where document_approval.request_id = document_approval_request.id
    and document_approval.next_request_id is null
  )
$$
language sql stable strict;

comment on function public.document_approval_request_approved is '@notNull';

----

create function public.document_approval_request_rejected(
  document_approval_request public.document_approval_request
) returns boolean as
$$
  select exists (
    select 1 from public.document_approval
    where (
      document_approval.request_id = document_approval_request.id
    ) and (
      document_approval.next_request_id is not null
    )
  )
$$
language sql stable strict;

comment on function public.document_approval_request_rejected is '@notNull';

----

create function public.is_document_approval_request_open(
  document_approval_request_id uuid
) returns boolean as
$$
  select not exists (select 1 from public.document_approval where request_id = document_approval_request_id)
$$
language sql stable strict;

create function public.document_approval_request_open(
  document_approval_request public.document_approval_request
) returns boolean as
$$
  select public.is_document_approval_request_open(document_approval_request.id)
$$
language sql stable strict;

comment on function public.document_approval_request_open is E'@notNull\nDoes the `DocumentApprovalRequest` have the related `DocumentApproval`. If it does not, it is still `open`.';

----

create function public.is_document_approved(
  document_id uuid
) returns boolean as
$$
  with recursive approval_chain as (
    select document_approval.*
    from public.document_approval_request
      left join public.document_approval
      on document_approval.request_id = document_approval_request.id
    where document_approval_request.document_id = is_document_approved.document_id
    and (
      -- not approved
      document_approval is null
      or (
        -- or not rejected and not canceled
        document_approval.next_request_id is null -- follow the chain but dont include the rejections
        and not document_approval.canceled -- dont include cancellations (canceled approval requests are as if they never happened)
      ))

    union

    select document_approval.*
    from approval_chain, public.document_approval
    where approval_chain.next_request_id = document_approval.request_id
  )
  select every(not (approval_chain is null))
  from approval_chain
$$
language sql stable strict;

create function public.document_approved(
  document public.document
) returns boolean as
$$
  select public.is_document_approved(document.id)
$$
language sql stable strict;

comment on function public.document_approved is 'Is the `Document` approved? Will return `null` when there are no `DocumentApprovalRequest`s.';

----

create function public.is_document_approved_without_verifiers(
  document_id uuid
) returns boolean as
$$
  with recursive approval_chain as (
    select document_approval.*
    from public.document_approval_request
      left join public.document_approval
      on document_approval.request_id = document_approval_request.id
    where document_approval_request.document_id = is_document_approved_without_verifiers.document_id
    and document_approval_request.blank_approver_type is distinct from 'VERIFIER'
    and (
      -- not approved
      document_approval is null
      or (
        -- or not rejected and not canceled
        document_approval.next_request_id is null -- follow the chain but dont include the rejections
        and not document_approval.canceled -- dont include cancellations (canceled approval requests are as if they never happened)
      ))

    union

    select document_approval.*
    from approval_chain, public.document_approval
    where approval_chain.next_request_id = document_approval.request_id
  )
  select every(not (approval_chain is null))
  from approval_chain
$$
language sql stable strict;

create function public.document_approved_without_verifiers(
  document public.document
) returns boolean as
$$
  select public.is_document_approved_without_verifiers(document.id)
$$
language sql stable strict;

comment on function public.document_approved_without_verifiers is 'Is the `Document` approved skipping verifier approval requests? Will return `null` when there are no `DocumentApprovalRequest`s.';
