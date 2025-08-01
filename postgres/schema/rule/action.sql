create table rule.action (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    name              text not null check (length(name) > 3),
    unique(client_company_id, name),

    description text,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time not null,
    created_at created_time not null
);

grant all on rule.action to domonda_user;
grant select on rule.action to domonda_wg_user;

----

create function rule.create_action(
    client_company_id uuid,
    name              text,
    description       text = null
) returns rule.action as
$$
    insert into rule.action (client_company_id, name, description, created_by)
    values (
        create_action.client_company_id,
        create_action.name,
        create_action.description,
        private.current_user_id()
    )
    returning *
$$
language sql volatile;

----

create function rule.update_action(
    id          uuid,
    name        text,
    description text = null
) returns rule.action as
$$
    update rule.action
    set
        name=update_action.name,
        description=update_action.description,
        updated_by=private.current_user_id(),
        updated_at=now()
    where id = update_action.id
    returning *
$$
language sql volatile;

----

create function rule.delete_action(
    id uuid
) returns rule.action as
$$
    delete from rule.action
    where id = delete_action.id
    returning *
$$
language sql volatile strict;
