create function control.add_client_company_user(
    user_id                        uuid,
    client_company_id              uuid,
    role_name                      text,
    document_accounting_tab_access public.document_accounting_tab_access = null,
    approver_limit                 float8 = null
) returns control.client_company_user as
$$
declare
    new_client_company_user     record;
    document_workflow_access_id uuid;
begin
    insert into control.client_company_user (id, user_id, client_company_id, role_name, document_accounting_tab_access, approver_limit) values
        (uuid_generate_v4(), add_client_company_user.user_id, add_client_company_user.client_company_id, add_client_company_user.role_name, add_client_company_user.document_accounting_tab_access, add_client_company_user.approver_limit)
    returning * into new_client_company_user;

    insert into control.document_filter (client_company_user_id, has_workflow_step, has_invoice) values
        (new_client_company_user.id, null, null);

    insert into control.document_category_access (id, client_company_user_id, document_category_id) values
        (uuid_generate_v4(), new_client_company_user.id, null);

    insert into control.document_workflow_access (id, client_company_user_id, document_workflow_id) values
        (uuid_generate_v4(), new_client_company_user.id, null)
    returning id into document_workflow_access_id;

    insert into control.document_workflow_step_access (id, document_workflow_access_id, document_workflow_step_id) values
        (uuid_generate_v4(), document_workflow_access_id, null);

    return new_client_company_user;
end;
$$
language plpgsql volatile;

----

create function control.add_client_company_user_for_client_company_ids(
    user_id                        uuid,
    client_company_ids             uuid[],
    role_name                      text,
    document_accounting_tab_access public.document_accounting_tab_access = null,
    approver_limit                 float8 = null
) returns setof control.client_company_user as
$$
declare
    client_company_id           uuid;
    new_client_company_user     record;
    document_workflow_access_id uuid;
begin
    foreach client_company_id in array add_client_company_user_for_client_company_ids.client_company_ids loop
        begin
            insert into control.client_company_user (id, user_id, client_company_id, role_name, document_accounting_tab_access, approver_limit) values
                (uuid_generate_v4(), add_client_company_user_for_client_company_ids.user_id, client_company_id, add_client_company_user_for_client_company_ids.role_name, add_client_company_user_for_client_company_ids.document_accounting_tab_access, add_client_company_user_for_client_company_ids.approver_limit)
            returning * into new_client_company_user;

            insert into control.document_filter (client_company_user_id, has_workflow_step, has_invoice) values
                (new_client_company_user.id, null, null);

            insert into control.document_category_access (id, client_company_user_id, document_category_id) values
                (uuid_generate_v4(), new_client_company_user.id, null);

            insert into control.document_workflow_access (id, client_company_user_id, document_workflow_id) values
                (uuid_generate_v4(), new_client_company_user.id, null)
            returning id into document_workflow_access_id;

            insert into control.document_workflow_step_access (id, document_workflow_access_id, document_workflow_step_id) values
                (uuid_generate_v4(), document_workflow_access_id, null);

            exception when unique_violation then
                -- keep looping
        end;

        return next new_client_company_user;
    end loop;

    return;
end;
$$
language plpgsql volatile;

----

create function control.add_client_company_user_for_user_ids(
    user_ids                       uuid[],
    client_company_id              uuid,
    role_name                      text,
    document_accounting_tab_access public.document_accounting_tab_access = null,
    approver_limit                 float8 = null
) returns setof control.client_company_user as
$$
declare
    user_id                     uuid;
    new_client_company_user     record;
    document_workflow_access_id uuid;
begin
    foreach user_id in array add_client_company_user_for_user_ids.user_ids loop
        insert into control.client_company_user (id, user_id, client_company_id, role_name, document_accounting_tab_access, approver_limit) values
            (uuid_generate_v4(), user_id, add_client_company_user_for_user_ids.client_company_id, add_client_company_user_for_user_ids.role_name, add_client_company_user_for_user_ids.document_accounting_tab_access, add_client_company_user_for_user_ids.approver_limit)
        returning * into new_client_company_user;

        insert into control.document_filter (client_company_user_id, has_workflow_step, has_invoice) values
            (new_client_company_user.id, null, null);

        insert into control.document_category_access (id, client_company_user_id, document_category_id) values
            (uuid_generate_v4(), new_client_company_user.id, null);

        insert into control.document_workflow_access (id, client_company_user_id, document_workflow_id) values
            (uuid_generate_v4(), new_client_company_user.id, null)
        returning id into document_workflow_access_id;

        insert into control.document_workflow_step_access (id, document_workflow_access_id, document_workflow_step_id) values
            (uuid_generate_v4(), document_workflow_access_id, null);

        return next new_client_company_user;
    end loop;

    return;
end;
$$
language plpgsql volatile;

----

create function control.add_accounting_company_user_to_client_companies(
    user_id                              uuid,
    accounting_company_client_company_id uuid,
    role_name                            text,
    document_accounting_tab_access       public.document_accounting_tab_access = null,
    approver_limit                       float8 = null
) returns bigint as
$$
declare
	company_id uuid;
    num_added  bigint;
begin
    num_added := 0;

    for company_id in
        (
            select cc.company_id from public.client_company as cc
                left join control.client_company_user as ccu on (ccu.client_company_id = cc.company_id) and (ccu.user_id = add_accounting_company_user_to_client_companies.user_id)
                where
                    (cc.accounting_company_client_company_id = add_accounting_company_user_to_client_companies.accounting_company_client_company_id)
                    and
                    (ccu.user_id is null)
        )
    loop
        begin
            perform control.add_client_company_user(add_accounting_company_user_to_client_companies.user_id, company_id, add_accounting_company_user_to_client_companies.role_name, add_accounting_company_user_to_client_companies.document_accounting_tab_access, add_accounting_company_user_to_client_companies.approver_limit);
            num_added := num_added + 1;
        exception when unique_violation then
            -- keep looping
        end;
    end loop;

    return num_added;
end;
$$
language plpgsql volatile;

----

create function control.add_all_accounting_company_users_to_client_company(
    accounting_company_client_company_id uuid,
    client_company_id                    uuid,
    role_name                            text,
    document_accounting_tab_access       public.document_accounting_tab_access = null,
    approver_limit                       float8 = null
) returns bigint as
$$
declare
	user_id   uuid;
    num_added bigint;
begin
    num_added := 0;

    for user_id in
        (
            select u.id from public.user as u
                where (u.client_company_id = add_all_accounting_company_users_to_client_company.accounting_company_client_company_id)
        )
    loop
        begin
            perform control.add_client_company_user(user_id, add_all_accounting_company_users_to_client_company.client_company_id, add_all_accounting_company_users_to_client_company.role_name, add_all_accounting_company_users_to_client_company.document_accounting_tab_access, add_all_accounting_company_users_to_client_company.approver_limit);
            num_added := num_added + 1;
        exception when unique_violation then
            -- keep looping
        end;
    end loop;

    return num_added;
end;
$$
language plpgsql volatile;

----

create function control.add_all_accounting_company_users_to_client_companies(
    accounting_company_client_company_id uuid,
    role_name                            text,
    document_accounting_tab_access       public.document_accounting_tab_access = null,
    approver_limit                       float8 = null
) returns bigint as
$$
declare
	user_id       uuid;
    num_added     bigint;
    num_sub_added bigint;
begin
    num_added := 0;

    for user_id in
        (
            select u.id from public.user as u
                where (u.client_company_id = add_all_accounting_company_users_to_client_companies.accounting_company_client_company_id)
        )
    loop
        select * into num_sub_added from control.add_accounting_company_user_to_client_companies(user_id, add_all_accounting_company_users_to_client_companies.accounting_company_client_company_id, add_all_accounting_company_users_to_client_companies.role_name, add_all_accounting_company_users_to_client_companies.document_accounting_tab_access, add_all_accounting_company_users_to_client_companies.approver_limit);
        num_added := num_added + num_sub_added;
    end loop;

    return num_added;
end;
$$
language plpgsql volatile;

-----

create function control.delete_client_company_user(
    user_id           uuid,
    client_company_id uuid
) returns control.client_company_user as
$$
declare
    deleted record;
begin
    delete from control.client_company_user as ccu where (
        ccu.user_id = delete_client_company_user.user_id
    ) and (
        ccu.client_company_id = delete_client_company_user.client_company_id
    )
    returning ccu.* into deleted;

    if deleted is null then
        raise exception using message = 'deleted row violates row-level security policy';
    end if;

    return deleted;
end;
$$
language plpgsql volatile strict;
