create type public.document_accounting_tab_access as enum (
    'VIEW',
    'EDIT'
);

----

-- view     = can view (mostly for quick navigation point adjustments, as the actual view filter is applied through other constrol tables)
-- add      = can insert
-- update   = can update
-- delete   = can delete

create table control.client_company_user_role (
    name text primary key,

    -- company
    update_company bool not null default false,

    -- client_companies
    view_client_companies   bool not null default false,
    add_client_companies    bool not null default false,
    update_client_companies bool not null default false,
    delete_client_companies bool not null default false,

    -- document_categories
    view_document_categories   bool not null default false,
    add_document_categories    bool not null default false,
    update_document_categories bool not null default false,
    delete_document_categories bool not null default false,

    -- users
    view_users   bool not null default false,
    add_users    bool not null default false,
    update_users bool not null default false,
    delete_users bool not null default false,

    -- documents (applies to invoices, delivery_notes)
    view_documents   bool not null default false,
    add_documents    bool not null default false,
    update_documents bool not null default false,
    delete_documents bool not null default false,

    -- money_accounts
    view_money_accounts   bool not null default false,
    add_money_accounts    bool not null default false,
    update_money_accounts bool not null default false,
    delete_money_accounts bool not null default false,

    -- money_transactions
    view_money_transactions bool not null default false
);

grant select on table control.client_company_user_role to domonda_user;

-- necessary because of the filter_users's `has_access_to_client_company`
grant select on table control.client_company_user_role to domonda_wg_user;

----

create table control.client_company_user (
    id uuid primary key,

    user_id             uuid not null references public.user(id) on delete cascade,
    client_company_id   uuid not null references public.client_company(company_id) on delete cascade,
    unique (user_id, client_company_id),

    role_name varchar not null references control.client_company_user_role(name) on delete cascade,

    document_accounting_tab_access public.document_accounting_tab_access,

    approver_limit float8,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select, insert, update, delete on table control.client_company_user to domonda_user;

-- select required by:
-- public.filter_users
grant select on table control.client_company_user to domonda_wg_user;

create index control_client_company_user_user_id_idx on control.client_company_user (user_id);
create index control_client_company_user_client_company_id_idx on control.client_company_user (client_company_id);
create index control_client_company_user_role_name_idx on control.client_company_user (role_name);

----

create function control.update_client_company_user(
    id                             uuid,
    user_id                        uuid,
    client_company_id              uuid,
    role_name                      varchar,
    document_accounting_tab_access public.document_accounting_tab_access = null,
    approver_limit                 float8 = null
) returns control.client_company_user as
$$
    update control.client_company_user set
        user_id=update_client_company_user.user_id,
        client_company_id=update_client_company_user.client_company_id,
        role_name=update_client_company_user.role_name,
        document_accounting_tab_access=update_client_company_user.document_accounting_tab_access,
        approver_limit=update_client_company_user.approver_limit,
        updated_at=now()
    where (id = update_client_company_user.id)
    returning *
$$
language sql volatile;

comment on function control.update_client_company_user is 'Updates the `ClientCompanyUser`.';

----

create function public.client_company_client_company_user_by_client_company_id(
	client_company public.client_company,
	user_id				 uuid
) returns control.client_company_user as
$$
	select * from control.client_company_user where (
		client_company_id = client_company_client_company_user_by_client_company_id.client_company.company_id
	) and (
		user_id = client_company_client_company_user_by_client_company_id.user_id
	)
$$
language sql stable;

comment on function public.client_company_client_company_user_by_client_company_id is 'Retrieves the `ClientCompanyUser` for the `ClientCompany` matching the `User` by the `userId`.';

----

create function public.user_client_company_user_by_client_company_id(
    "user"            public.user,
    client_company_id uuid
) returns control.client_company_user as
$$
    select * from control.client_company_user
    where (
		user_id = user_client_company_user_by_client_company_id."user".id
	) and (
        client_company_id = user_client_company_user_by_client_company_id.client_company_id
	)
$$
language sql stable;

----

create function public.delete_user_group_user_on_client_company_user_delete()
returns trigger as $$
  begin
    delete from public.user_group_user
    using public.user_group
    where user_group_user.user_group_id = user_group.id
    and user_group_user.user_id = old.user_id
    and user_group.client_company_id = old.client_company_id;

    return null;
  end
$$ language plpgsql volatile;

create trigger delete_user_group_user_on_client_company_user_delete_trigger
  after delete
  on control.client_company_user
  for each row
  execute procedure public.delete_user_group_user_on_client_company_user_delete();
