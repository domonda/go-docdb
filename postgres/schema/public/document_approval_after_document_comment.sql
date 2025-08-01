create function public.create_document_approval_request(
  document_id uuid,
  approver_id uuid = null,
  user_group_id uuid = null,
  message jsonb = null
) returns public.document_approval_request as
$$
declare
  request public.document_approval_request;
begin
  insert into public.document_approval_request (document_id, requester_id, approver_id, user_group_id)
    values (
      create_document_approval_request.document_id,
      private.current_user_id(),
      create_document_approval_request.approver_id,
      create_document_approval_request.user_group_id
    )
  returning * into request;

  if create_document_approval_request.message is not null then
    perform public.create_document_comment(
      document_id=>create_document_approval_request.document_id,
      message=>create_document_approval_request.message,
      related_document_approval_request_id=>request.id
    );
  end if;

  return request;
end
$$
language plpgsql volatile;

create function public.create_blank_document_approval_requests(
  document_id         uuid,
  number_of_requests  integer,
  blank_approver_type public.document_approval_request_blank_approver_type,
  message             jsonb = null
) returns public.document as
$$
declare
  document public.document;
  request  public.document_approval_request;
  requests public.document_approval_request[];
begin
  if number_of_requests is null then
    raise exception 'Number of requests cannot be empty';
  end if;

  if number_of_requests < 1 then
    raise exception 'Number of requests must not be negative and must be greater than zero';
  end if;

  if number_of_requests > 10 then
    raise exception 'Only 10 requests can be created at a time';
  end if;

  for i in 1..number_of_requests
  loop
    insert into public.document_approval_request (document_id, requester_id, blank_approver_type)
    values (
      create_blank_document_approval_requests.document_id,
      private.current_user_id(),
      create_blank_document_approval_requests.blank_approver_type
    )
    returning * into request;

    requests := array_append(requests, request);
  end loop;

  if create_blank_document_approval_requests.message is not null then
    if number_of_requests = 1 then

      perform public.create_document_comment(
        document_id=>create_blank_document_approval_requests.document_id,
        message=>create_blank_document_approval_requests.message,
        related_document_approval_request_id=>requests[1].id
      );

    else

      -- TODO: how to relate multiple approval requests to a single comment?
      perform public.create_document_comment(
        document_id=>create_blank_document_approval_requests.document_id,
        message=>create_blank_document_approval_requests.message
      );

    end if;
  end if;

  select * into document
  from public.document
  where id = create_blank_document_approval_requests.document_id;

  return document;
end;
$$
language plpgsql volatile;

create function public.reject_document(
  reject_request_id   uuid,
  request_message     jsonb, -- message is required when rejecting
  blank_approver_type public.document_approval_request_blank_approver_type = null,
  request_approver_id uuid = null,
  request_user_group_id uuid = null
) returns public.document_approval as
$$
declare
  request_document_id uuid;
  document_approval_id uuid := uuid_generate_v4();
  document_approval_request_id uuid := uuid_generate_v4();
  new_document_approval public.document_approval;
begin
  select document_id into request_document_id
  from public.document_approval_request
  where id = reject_document.reject_request_id;

  insert into public.document_approval_request (id, document_id, requester_id, approver_id, user_group_id, blank_approver_type, created_at)
  values (
    document_approval_request_id,
    request_document_id,
    private.current_user_id(),
    reject_document.request_approver_id,
    reject_document.request_user_group_id,
    reject_document.blank_approver_type,
    now()
  );

  insert into public.document_approval (id, request_id, approver_id, next_request_id)
  values (
    document_approval_id,
    reject_document.reject_request_id,
    private.current_user_id(),
    document_approval_request_id
  )
  returning * into new_document_approval;

  if reject_document.request_message is not null then
    perform public.create_document_comment(
      document_id=>request_document_id,
      message=>reject_document.request_message,
      related_document_approval_id=>document_approval_id
    );
  end if;

  return new_document_approval;
end
$$
language plpgsql volatile;

create function public.cancel_document_approval_request(
  document_approval_request_id uuid,
  message jsonb = null
) returns public.document_approval as
$$
declare
  document_id uuid;
  approval public.document_approval;
begin
  insert into public.document_approval (request_id, approver_id, canceled)
    values (
      cancel_document_approval_request.document_approval_request_id,
      private.current_user_id(),
      true
    )
  returning * into approval;

  if cancel_document_approval_request.message is not null then
    select document_approval_request.document_id into document_id
    from public.document_approval_request
    where id = cancel_document_approval_request.document_approval_request_id;
    perform public.create_document_comment(
      document_id=>document_id,
      message=>cancel_document_approval_request.message,
      related_document_approval_id=>approval.id
    );
  end if;

  return approval;
end
$$
language plpgsql volatile;
