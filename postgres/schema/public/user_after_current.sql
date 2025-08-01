create function public.update_user(
  id                                            uuid,
  client_company_id                             uuid,
  "language"                                    language_code,
  first_name                                    text,
  last_name                                     text = null,
  title                                         text = null,
  domonda_update_notification                   int = 0,
  document_direct_approval_request_notification boolean = true,
  document_group_approval_request_notification  boolean = true
) returns public.user as $$
    update public.user set
      client_company_id=update_user.client_company_id,
      "language"=update_user."language",
      title=update_user.title,
      first_name=update_user.first_name,
      last_name=update_user.last_name,
      domonda_update_notification=update_user.domonda_update_notification,
      document_direct_approval_request_notification=update_user.document_direct_approval_request_notification,
      document_group_approval_request_notification=update_user.document_group_approval_request_notification,
      updated_by=private.current_user_id(),
      updated_at=now()
    where id = update_user.id
    returning *
$$ language sql volatile;

comment on function public.update_user is 'Updates the `User`.';

----

create function public.update_user_language(
  id         uuid,
  "language" language_code
) returns public.user as $$
  update public.user set
    "language"=update_user_language."language",
    updated_by=private.current_user_id(),
    updated_at=now()
  where id = update_user_language.id
  returning *
$$ language sql volatile;

comment on function public.update_user_language is 'Updates the `User`''s lanugage.';
