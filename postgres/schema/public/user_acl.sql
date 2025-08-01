create function public.user_has_admin_access_for_client_company(
  "user" public.user,
  client_company_id uuid
) returns boolean as $$
declare
  has boolean;
begin
  if public.current_user_is_wg()
    then return false;
  end if;

  select (
    public.user_is_super_admin("user")
    or exists (
      select from public.user_client_company_user_by_client_company_id("user", client_company_id)
      where role_name = 'ADMIN'
    )
  ) into has;

  return has;
end;
$$ language plpgsql stable strict;
comment on function public.user_has_admin_access_for_client_company is '@notNull';

create function public.client_company_current_user_has_admin_access(
  client_company public.client_company
) returns boolean as $$
  select public.user_has_admin_access_for_client_company(
    private.current_user(),
    client_company.company_id
  )
$$ language sql stable strict;
comment on function public.client_company_current_user_has_admin_access is '@notNull';

----

create function public.user_has_accounting_access_for_client_company(
  "user"            public.user,
  client_company_id uuid
) returns boolean as $$
declare
  has boolean;
begin
  if public.current_user_is_wg()
    then return false;
  end if;

  select (
    public.user_is_super_admin("user")
    or public.user_has_admin_access_for_client_company("user", client_company_id)
    or exists (
      select from public.user_client_company_user_by_client_company_id("user", client_company_id)
      where role_name = 'ACCOUNTANT'
    )
  ) into has;

  return has;
end;
$$ language plpgsql stable strict;
comment on function public.user_has_accounting_access_for_client_company is '@notNull';

create function public.client_company_current_user_has_accounting_access(
  client_company public.client_company
) returns boolean as $$
  select public.user_has_accounting_access_for_client_company(
    private.current_user(),
    client_company.company_id
  )
$$ language sql stable strict;
comment on function public.client_company_current_user_has_accounting_access is '@notNull';

----

create function public.user_has_banking_access_for_client_company(
  "user"            public.user,
  client_company_id uuid
) returns boolean as $$
declare
  has boolean;
begin
  if public.current_user_is_wg()
    then return false;
  end if;

  select (
    public.user_is_super_admin("user")
    or public.user_has_admin_access_for_client_company("user", client_company_id)
    or public.user_has_accounting_access_for_client_company("user", client_company_id)
    or exists (
      select from public.user_client_company_user_by_client_company_id("user", client_company_id)
      where role_name = 'CLIENT'
    )
  ) into has;

  return has;
end;
$$ language plpgsql stable strict;
comment on function public.user_has_banking_access_for_client_company is '@notNull';

create function public.client_company_current_user_has_banking_access(
  client_company public.client_company
) returns boolean as $$
  select public.user_has_banking_access_for_client_company(
    private.current_user(),
    client_company.company_id
  )
$$ language sql stable strict;
comment on function public.client_company_current_user_has_banking_access is '@notNull';

----

create function public.user_has_verifying_access_for_client_company(
  "user"            public.user,
  client_company_id uuid
) returns boolean as $$
declare
  has boolean;
begin
  if public.current_user_is_wg()
    then return false;
  end if;

  select exists (
    select from public.user_client_company_user_by_client_company_id("user", client_company_id)
    where role_name = 'VERIFIER'
  ) into has;

  return has;
end;
$$ language plpgsql stable strict;
comment on function public.user_has_verifying_access_for_client_company is '@notNull';

create function public.client_company_current_user_has_verifying_access(
  client_company public.client_company
) returns boolean as $$
  select public.user_has_verifying_access_for_client_company(
    private.current_user(),
    client_company.company_id
  )
$$ language sql stable strict;
comment on function public.client_company_current_user_has_verifying_access is '@notNull';

----

create function public.user_has_company_manage_access_for_client_company(
  "user"            public.user,
  client_company_id uuid
) returns boolean as $$
declare
  has boolean;
begin
  if public.current_user_is_wg()
    then return false;
  end if;

  select (
    public.user_is_super_admin("user")
    or exists (
      select from public.user_client_company_user_by_client_company_id("user", client_company_id)
      where role_name in (
        'ADMIN',
        'ACCOUNTANT',
        'VERIFIER', -- needs to change partners
        'CLIENT'
      )
    )
  ) into has;

  return has;
end;
$$ language plpgsql stable strict;
comment on function public.user_has_company_manage_access_for_client_company is '@notNull';

create function public.client_company_current_user_has_company_manage_access(
  client_company public.client_company
) returns boolean as $$
  select public.user_has_company_manage_access_for_client_company(
    private.current_user(),
    client_company.company_id
  )
$$ language sql stable strict;
comment on function public.client_company_current_user_has_company_manage_access is '@notNull';

----

create function public.user_has_client_company_manage_access_for_client_company(
  "user"            public.user,
  client_company_id uuid
) returns boolean as $$
declare
  has boolean;
begin
  if public.current_user_is_wg()
    then return false;
  end if;

  select (
    public.user_is_super_admin("user")
    or exists (
      select from public.user_client_company_user_by_client_company_id("user", client_company_id)
      where role_name in (
        'ADMIN',
        'ACCOUNTANT'
      )
    )
  ) into has;

  return has;
end;
$$ language plpgsql stable strict;
comment on function public.user_has_client_company_manage_access_for_client_company is '@notNull';

create function public.client_company_current_user_has_client_company_manage_access(
  client_company public.client_company
) returns boolean as $$
  select public.user_has_client_company_manage_access_for_client_company(
    private.current_user(),
    client_company.company_id
  )
$$ language sql stable strict;
comment on function public.client_company_current_user_has_client_company_manage_access is '@notNull';

----

create function public.user_has_company_tags_manage_access_for_client_company(
  "user"            public.user,
  client_company_id uuid
) returns boolean as $$
declare
  has boolean;
begin
  if public.current_user_is_wg()
    then return false;
  end if;

  select (
    public.user_is_super_admin("user")
    or exists (
      select from public.user_client_company_user_by_client_company_id("user", client_company_id)
      where role_name in (
        'ADMIN',
        'ACCOUNTANT',
        'CLIENT'
      )
    )
  ) into has;

  return has;
end;
$$ language plpgsql stable strict;
comment on function public.user_has_company_tags_manage_access_for_client_company is '@notNull';

create function public.client_company_current_user_has_company_tags_manage_access(
  client_company public.client_company
) returns boolean as $$
  select public.user_has_company_tags_manage_access_for_client_company(
    private.current_user(),
    client_company.company_id
  )
$$ language sql stable strict;
comment on function public.client_company_current_user_has_company_tags_manage_access is '@notNull';

----

create function public.user_has_documents_manage_access_for_client_company(
  "user"            public.user,
  client_company_id uuid
) returns boolean as $$
declare
  has boolean;
begin
  if public.current_user_is_wg()
    then return false;
  end if;

  select (
    public.user_is_super_admin("user")
    or exists (
      select from public.user_client_company_user_by_client_company_id("user", client_company_id)
      where role_name in (
        'DEFAULT',
        'ADMIN',
        'ACCOUNTANT',
        'CLIENT',
        'DOCUMENTS_ONLY',
        'VERIFIER'
      )
    )
  ) into has;

  return has;
end;
$$ language plpgsql stable strict;
comment on function public.user_has_documents_manage_access_for_client_company is '@notNull';

create function public.client_company_current_user_has_documents_manage_access(
  client_company public.client_company
) returns boolean as $$
  select public.user_has_documents_manage_access_for_client_company(
    private.current_user(),
    client_company.company_id
  )
$$ language sql stable strict;
comment on function public.client_company_current_user_has_documents_manage_access is '@notNull';

----

create function public.client_company_current_user_has_document_workflow_restrictions(
  client_company public.client_company
) returns boolean as $$
  select exists (
    select from control.document_workflow_step_access
      inner join control.document_workflow_access on document_workflow_access.id = document_workflow_step_access.document_workflow_access_id
      inner join control.client_company_user on client_company_user.id = document_workflow_access.client_company_user_id
    where client_company_user.user_id = (select private.current_user_id())
    and client_company_user.client_company_id = client_company.company_id
    and document_workflow_step_access.document_workflow_step_id is not null)
$$ language sql stable strict;
comment on function public.client_company_current_user_has_document_workflow_restrictions is '@notNull';
