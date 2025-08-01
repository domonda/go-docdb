create type rule.document_macro_reaction_name as enum (
  'SIGNA_COMPANY_GA_TO_PRUEFER1',
  'SIGNA_COMPANY_GA_TO_PRUEFER2',
  'SIGNA_COMPANY_GA_TO_FREIGEBER1',
  'SIGNA_COMPANY_GA_TO_FREIGEBER2',
  'SIGNA_COMPANY_EMAIL_TO_ABLEHNUNG',
  'SIGNA_COMPANY_EMAIL_TO_CLEARING'
);

create table rule.document_macro_reaction (
  reaction_id uuid primary key references rule.reaction(id) on delete cascade,

  macro rule.document_macro_reaction_name not null,

  created_by uuid not null
    default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
    references public.user(id) on delete set default,
  updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

  created_at created_time not null,
  updated_at updated_time not null
);

grant all on rule.document_macro_reaction to domonda_user;
grant select on rule.document_macro_reaction to domonda_wg_user;

create index rule_document_macro_reaction_macro_idx on rule.document_macro_reaction (macro);

----

create function rule.check_document_macro_reaction_is_used()
returns trigger as $$
declare
  rec rule.document_macro_reaction;
begin
  if TG_OP = 'DELETE' then
    rec = OLD;
  else
    rec = NEW;
  end if;

  if exists (select from rule.action_reaction where action_reaction.reaction_id = rec.reaction_id)
    and not rule.current_user_is_special()
  then
    raise exception 'Reaction is in use';
  end if;

  return rec;
end
$$ language plpgsql stable;

create trigger rule_check_document_macro_reaction_is_used_trigger
  before insert or update or delete
  on rule.document_macro_reaction
  for each row
  execute procedure rule.check_document_macro_reaction_is_used();

----

create function rule.create_document_macro_reaction(
  reaction_id uuid,
  macro rule.document_macro_reaction_name
) returns rule.document_macro_reaction as
$$
  insert into rule.document_macro_reaction (reaction_id, macro, created_by)
  values (
    create_document_macro_reaction.reaction_id,
    create_document_macro_reaction.macro,
    private.current_user_id()
  )
  returning *
$$
language sql volatile;

create function rule.update_document_macro_reaction(
  reaction_id uuid,
  macro rule.document_macro_reaction_name
) returns rule.document_macro_reaction as
$$
  update rule.document_macro_reaction
  set
    macro=update_document_macro_reaction.macro,
    updated_by=private.current_user_id(),
    updated_at=now()
  where reaction_id = update_document_macro_reaction.reaction_id
  returning *
$$
language sql volatile;

create function rule.delete_document_macro_reaction(
  reaction_id uuid
) returns rule.document_macro_reaction as
$$
  delete from rule.document_macro_reaction
  where reaction_id = delete_document_macro_reaction.reaction_id
  returning *
$$
language sql volatile strict;

----

create function rule.do_document_macro_reaction(
  action_reaction rule.action_reaction,
  macro           rule.document_macro_reaction_name,
  document        public.document
) returns public.document as $$
declare
  approver_email public.email_addr;
  notif_email public.email_addr;
  notif private.notification;
  added_client_company_user control.client_company_user;
begin
  case macro
  when 'SIGNA_COMPANY_GA_TO_PRUEFER1'
  then
    for approver_email in (
      select distinct email_address_prop.value
      from document_category_object_instance
        inner join object.email_address_prop
        on email_address_prop.instance_id = document_category_object_instance.object_instance_id
      where email_address_prop.class_prop_id = '0fc9e168-0610-4cec-a4d0-ec0697ba2022' -- Prüfer
      and document_category_object_instance.document_category_id = document.category_id
    ) loop

      if not exists (select from public.user where "user".email = approver_email)
      then
        -- create a placeholder user because the user might've not been registered yet
        -- https://app.asana.com/1/201241326692307/project/1138407765982241/task/1209668500177154?focus=true
        insert into public."user" (client_company_id, auth0_user_id, first_name, email, created_by)
        values (
          '458c3207-3cb5-4c15-bb76-1c1db57140cd', -- matches SIGNA_CLIENT_COMPANY_ID in domonda-graphql
          null,
          split_part(approver_email, '@', 1),
          approver_email,
          'bde919f0-3e23-4bfa-81f1-abff4f45fb51' -- Rule
        );
      end if;

      if not exists (select from control.client_company_user
          inner join public.user on "user".id = client_company_user.user_id
        where "user".email = approver_email
        and client_company_user.client_company_id = document.client_company_id)
      then
        select * into added_client_company_user
        from control.add_client_company_user(
          user_id=>(select id from public.user where "user".email = approver_email),
          client_company_id=>document.client_company_id,
          role_name=>'DOCUMENTS_ONLY' -- matches how domonda-graphql/signa.ts assigns roles
        );
        update control.document_filter
        set has_approval_request=true
        where client_company_user_id = added_client_company_user.id;
        -- the user's access rights because they will be corrected on first login by domonda-graphql/signa.ts if necessary
      end if;

      insert into public.document_approval_request (document_id, requester_id, approver_id)
      select
        document.id,
        'bde919f0-3e23-4bfa-81f1-abff4f45fb51', -- Rule
        "user".id
      from public.user
      where "user".email = approver_email;

    end loop;
  when 'SIGNA_COMPANY_GA_TO_PRUEFER2'
  then
    for approver_email in (
      select distinct email_address_prop.value
      from document_category_object_instance
        inner join object.email_address_prop
        on email_address_prop.instance_id = document_category_object_instance.object_instance_id
      where email_address_prop.class_prop_id = 'ed7fd1ba-5e14-47f9-aabe-b67725b03b4f' -- Prüfer 2
      and document_category_object_instance.document_category_id = document.category_id
    ) loop

      if not exists (select from public.user where "user".email = approver_email)
      then
        -- create a placeholder user because the user might've not been registered yet
        -- https://app.asana.com/1/201241326692307/project/1138407765982241/task/1209668500177154?focus=true
        insert into public."user" (client_company_id, auth0_user_id, first_name, email, created_by)
        values (
          '458c3207-3cb5-4c15-bb76-1c1db57140cd', -- matches SIGNA_CLIENT_COMPANY_ID in domonda-graphql
          null,
          split_part(approver_email, '@', 1),
          approver_email,
          'bde919f0-3e23-4bfa-81f1-abff4f45fb51' -- Rule
        );
      end if;

      if not exists (select from control.client_company_user
          inner join public.user on "user".id = client_company_user.user_id
        where "user".email = approver_email
        and client_company_user.client_company_id = document.client_company_id)
      then
        select * into added_client_company_user
        from control.add_client_company_user(
          user_id=>(select id from public.user where "user".email = approver_email),
          client_company_id=>document.client_company_id,
          role_name=>'DOCUMENTS_ONLY' -- matches how domonda-graphql/signa.ts assigns roles
        );
        update control.document_filter
        set has_approval_request=true
        where client_company_user_id = added_client_company_user.id;
        -- the user's access rights because they will be corrected on first login by domonda-graphql/signa.ts if necessary
      end if;

      insert into public.document_approval_request (document_id, requester_id, approver_id)
      select
        document.id,
        'bde919f0-3e23-4bfa-81f1-abff4f45fb51', -- Rule
        "user".id
      from public.user
      where "user".email = approver_email;

    end loop;
  when 'SIGNA_COMPANY_GA_TO_FREIGEBER1'
  then
    for approver_email in (
      select distinct email_address_prop.value
      from document_category_object_instance
        inner join object.email_address_prop
        on email_address_prop.instance_id = document_category_object_instance.object_instance_id
      where email_address_prop.class_prop_id = '0c01543d-b1e9-44c8-a8f2-a7a6e6639006' -- Freigeber
      and document_category_object_instance.document_category_id = document.category_id
    ) loop

      if not exists (select from public.user where "user".email = approver_email)
      then
        -- create a placeholder user because the user might've not been registered yet
        -- https://app.asana.com/1/201241326692307/project/1138407765982241/task/1209668500177154?focus=true
        insert into public."user" (client_company_id, auth0_user_id, first_name, email, created_by)
        values (
          '458c3207-3cb5-4c15-bb76-1c1db57140cd', -- matches SIGNA_CLIENT_COMPANY_ID in domonda-graphql
          null,
          split_part(approver_email, '@', 1),
          approver_email,
          'bde919f0-3e23-4bfa-81f1-abff4f45fb51' -- Rule
        );
      end if;

      if not exists (select from control.client_company_user
          inner join public.user on "user".id = client_company_user.user_id
        where "user".email = approver_email
        and client_company_user.client_company_id = document.client_company_id)
      then
        select * into added_client_company_user
        from control.add_client_company_user(
          user_id=>(select id from public.user where "user".email = approver_email),
          client_company_id=>document.client_company_id,
          role_name=>'DOCUMENTS_ONLY' -- matches how domonda-graphql/signa.ts assigns roles
        );
        update control.document_filter
        set has_approval_request=true
        where client_company_user_id = added_client_company_user.id;
        -- the user's access rights because they will be corrected on first login by domonda-graphql/signa.ts if necessary
      end if;

      insert into public.document_approval_request (document_id, requester_id, approver_id)
      select
        document.id,
        'bde919f0-3e23-4bfa-81f1-abff4f45fb51', -- Rule
        "user".id
      from public.user
      where "user".email = approver_email;

    end loop;
  when 'SIGNA_COMPANY_GA_TO_FREIGEBER2'
  then
    for approver_email in (
      select distinct email_address_prop.value
      from document_category_object_instance
        inner join object.email_address_prop
        on email_address_prop.instance_id = document_category_object_instance.object_instance_id
      where email_address_prop.class_prop_id = 'a0fa0525-cec6-49c7-a598-1f8be051aec7' -- Freigeber 2
      and document_category_object_instance.document_category_id = document.category_id
    ) loop

      if not exists (select from public.user where "user".email = approver_email)
      then
        -- create a placeholder user because the user might've not been registered yet
        -- https://app.asana.com/1/201241326692307/project/1138407765982241/task/1209668500177154?focus=true
        insert into public."user" (client_company_id, auth0_user_id, first_name, email, created_by)
        values (
          '458c3207-3cb5-4c15-bb76-1c1db57140cd', -- matches SIGNA_CLIENT_COMPANY_ID in domonda-graphql
          null,
          split_part(approver_email, '@', 1),
          approver_email,
          'bde919f0-3e23-4bfa-81f1-abff4f45fb51' -- Rule
        );
      end if;

      if not exists (select from control.client_company_user
          inner join public.user on "user".id = client_company_user.user_id
        where "user".email = approver_email
        and client_company_user.client_company_id = document.client_company_id)
      then
        select * into added_client_company_user
        from control.add_client_company_user(
          user_id=>(select id from public.user where "user".email = approver_email),
          client_company_id=>document.client_company_id,
          role_name=>'DOCUMENTS_ONLY' -- matches how domonda-graphql/signa.ts assigns roles
        );
        update control.document_filter
        set has_approval_request=true
        where client_company_user_id = added_client_company_user.id;
        -- the user's access rights because they will be corrected on first login by domonda-graphql/signa.ts if necessary
      end if;

      insert into public.document_approval_request (document_id, requester_id, approver_id)
      select
        document.id,
        'bde919f0-3e23-4bfa-81f1-abff4f45fb51', -- Rule
        "user".id
      from public.user
      where "user".email = approver_email;

    end loop;
  when 'SIGNA_COMPANY_EMAIL_TO_ABLEHNUNG'
  then
    for notif_email in (
      select distinct email_address_prop.value
      from document_category_object_instance
        inner join object.email_address_prop
        on email_address_prop.instance_id = document_category_object_instance.object_instance_id
      where email_address_prop.class_prop_id = 'a5233100-420e-4802-ac48-5771f2228c92' -- Ablehnung Emailliste
      and document_category_object_instance.document_category_id = document.category_id
    ) loop

      notif := private.notify_document_info(
        destination=>'EMAIL',
        document=>document,
        receiver_email=>notif_email,
        action_reaction_id=>action_reaction.id
      );

      insert into rule.send_notification_log (action_reaction_id, document_id, notification_id)
          values (action_reaction.id, document.id, notif.id);

    end loop;
  when 'SIGNA_COMPANY_EMAIL_TO_CLEARING'
  then
    for notif_email in (
      select distinct email_address_prop.value
      from document_category_object_instance
        inner join object.email_address_prop
        on email_address_prop.instance_id = document_category_object_instance.object_instance_id
      where email_address_prop.class_prop_id = '8704900f-398f-402a-95a1-47a6aefe7a5a' -- Clearingstelle
      and document_category_object_instance.document_category_id = document.category_id
    ) loop

      notif := private.notify_document_info(
        destination=>'EMAIL',
        document=>document,
        receiver_email=>notif_email,
        action_reaction_id=>action_reaction.id
      );

      insert into rule.send_notification_log (action_reaction_id, document_id, notification_id)
          values (action_reaction.id, document.id, notif.id);

    end loop;
  else
    raise exception 'Unrecognized document macro reaction "%"', condition.macro;
  end case;

  return document;
end
$$ language plpgsql volatile strict
security definer; -- for creating users and other privileged operations
comment on function rule.do_document_macro_reaction is '@omit';

create function rule.do_document_macro_action_reaction(
  action_reaction rule.action_reaction,
  document        public.document
) returns public.document as $$
declare
  document_macro_reaction rule.document_macro_reaction;
begin
  if action_reaction."trigger" in ('ALWAYS', 'ONCE', 'DOCUMENT_CHANGED')
  and exists(select from rule.document_macro_log
    where document_macro_log.action_reaction_id = action_reaction.id
    and document_macro_log.document_id = document.id
    and (action_reaction."trigger" = 'ONCE'
      -- some triggers should not execute multiple times recursively
      or document_macro_log.created_at = now())
    )
  then
    return document;
  end if;

  -- find reaction
  select * into document_macro_reaction from rule.document_macro_reaction where reaction_id = action_reaction.reaction_id;

  -- if there is no reaction, return
  if document_macro_reaction is null then
    return document;
  end if;

  -- log
  insert into rule.document_macro_log (action_reaction_id, document_id, created_at)
    values (action_reaction.id, document.id, now());

  -- we log first then we react making sure recursive reactions dont happen

  -- react
  perform rule.do_document_macro_reaction(action_reaction, document_macro_reaction.macro, document);

  return document;
end
$$ language plpgsql volatile;
comment on function rule.do_document_macro_action_reaction is '@omit';
