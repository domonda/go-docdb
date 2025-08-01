create table rule.reaction (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    name              text not null check (length(name) > 3),
    unique(client_company_id, name),

    description text,

    created_by uuid not null
        default public.unknown_user_id()
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time not null,
    created_at created_time not null
);

grant all on rule.reaction to domonda_user;
grant select on rule.reaction to domonda_wg_user;

----

create function rule.create_reaction(
    client_company_id uuid,
    name              text,
    description       text = null
) returns rule.reaction as
$$
    insert into rule.reaction (client_company_id, name, description, created_by)
    values (
        create_reaction.client_company_id,
        create_reaction.name,
        create_reaction.description,
        private.current_user_id()
    )
    returning *
$$
language sql volatile;

----

create function rule.update_reaction(
    id          uuid,
    name        text,
    description text = null
) returns rule.reaction as
$$
    update rule.reaction
    set
        name=update_reaction.name,
        description=update_reaction.description,
        updated_by=private.current_user_id(),
        updated_at=now()
    where id = update_reaction.id
    returning *
$$
language sql volatile;

----

create function rule.delete_reaction(
    id uuid
) returns rule.reaction as
$$
    delete from rule.reaction
    where reaction.id = delete_reaction.id
    returning *
$$
language sql volatile strict;
