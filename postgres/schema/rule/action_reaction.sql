create type rule.action_reaction_trigger as enum (
    'ONCE',
    'ALWAYS',
    -- TODO 'DOCUMENT_IMPORTED'
    -- TODO 'DOCUMENT_EXTRACTED'
    'DOCUMENT_CHANGED',
    'DOCUMENT_CATEGORY_CHANGED',
    'DOCUMENT_APPROVAL', -- single approval
    'DOCUMENT_APPROVAL_ALL', -- all approvals (direct and group)
    'DOCUMENT_APPROVAL_DIRECT', -- single approval of a direct request
    'DOCUMENT_APPROVAL_GROUP', -- single approval of a group request
    'DOCUMENT_APPROVAL_USER_GROUP', -- single approval of a user group approval
    'DOCUMENT_APPROVAL_ALL_DIRECT', -- all direct requests have been approved
    'DOCUMENT_APPROVAL_ALL_USER_GROUP', -- all user group requests have been approved
    'DOCUMENT_REJECTION', -- single rejection
    'DOCUMENT_REJECTION_DIRECT', -- single rejection of a direct request
    'DOCUMENT_REJECTION_GROUP', -- single rejection of a group request
    'DOCUMENT_APPROVAL_CANCELLATION', -- single cancellation
    'DOCUMENT_APPROVAL_USER_CANCELLATION', -- single non-system user cancellation
    'DOCUMENT_WORKFLOW_CHANGED'
    -- TODO 'DOCUMENT_BOOKED',
    -- TODO 'DOCUMENT_EXPORTED',
    -- TODO 'DOCUMENT_PAID',
    -- TODO 'DOCUMENT_NEW_TAG',
    -- TODO 'DOCUMENT_NEW_COST_CENTER'
    -- TODO 'DOCUMENT_NEW_COST_UNIT'
);
comment on type rule.action_reaction_trigger is 'How many times should the action/reaction get triggered.';

----

-- TODO: implement check which guarantees that both action and reaction are from the same client company
create table rule.action_reaction (
    id uuid primary key default uuid_generate_v4(),

    "trigger" rule.action_reaction_trigger not null,

    action_id   uuid not null references rule.action(id) on delete restrict,
    reaction_id uuid not null references rule.reaction(id) on delete restrict,

    description text, -- deprecated

    disabled boolean not null default false,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    -- intentionally no uniqueness constraint for easier manipulation
    sort_index int not null default 500,
    constraint sort_index_range_check check(sort_index > 0 and sort_index < 1000),

    updated_at updated_time not null,
    created_at created_time not null
);

create unique index action_reaction_unique on rule.action_reaction ("trigger", action_id, reaction_id);
-- TODO create unique index action_reaction_unique_when_action_null on rule.action_reaction ("trigger", reaction_id) where (action_id is null);

grant all on rule.action_reaction to domonda_user;
grant select on rule.action_reaction to domonda_wg_user;

comment on column rule.action_reaction.description is '@deprecated The name should be derived from `Action` + `Reaction` instead.';

create function rule.action_reaction_update_action_or_reaction()
returns trigger as $$
begin
    if rule.action_reaction_was_triggered(old)
        and not rule.current_user_is_special()
    then
        raise exception 'Rule is in use and therefore cannot be updated';
    end if;
    return new;
end
$$ language plpgsql immutable;

create trigger rule_action_reaction_update_action_or_reaction_trigger
    before update
    on rule.action_reaction
    for each row
    when ((new."trigger" is distinct from old."trigger")
        or (new.action_id is distinct from old.action_id)
        or (new.reaction_id is distinct from old.reaction_id))
    execute procedure rule.action_reaction_update_action_or_reaction();

create function rule.action_reaction_delete_action_or_reaction()
returns trigger as $$
begin
    if rule.action_reaction_was_triggered(old)
        and not rule.current_user_is_special()
    then
        raise exception 'Rule is in use and therefore cannot be deleted';
    end if;
    return old;
end
$$ language plpgsql immutable;

create trigger rule_action_reaction_delete_action_or_reaction_trigger
    before delete
    on rule.action_reaction
    for each row
    execute procedure rule.action_reaction_delete_action_or_reaction();

----

create function rule.action_reaction_client_company_by_action_and_reaction(
    action_reaction rule.action_reaction
) returns public.client_company as
$$
    select cc.* from public.client_company as cc
        inner join rule.action as a on (a.id = action_reaction.action_id and a.client_company_id = cc.company_id)
        inner join rule.reaction as r on (r.id = action_reaction.reaction_id and r.client_company_id = cc.company_id)
$$
language sql stable strict;

comment on function rule.action_reaction_client_company_by_action_and_reaction is '@notNull';

----

create function rule.create_action_reaction(
    "trigger"   rule.action_reaction_trigger,
    action_id   uuid,
    reaction_id uuid,
    disabled    boolean = false,
    sort_index  int = 0
) returns rule.action_reaction as
$$
    insert into rule.action_reaction ("trigger", action_id, reaction_id, disabled, sort_index, created_by)
    values (
        create_action_reaction."trigger",
        create_action_reaction.action_id,
        create_action_reaction.reaction_id,
        create_action_reaction.disabled,
        sort_index,
        private.current_user_id()
    )
    returning *
$$
language sql volatile;

----

create function rule.update_action_reaction(
    id          uuid,
    "trigger"   rule.action_reaction_trigger,
    action_id   uuid,
    reaction_id uuid,
    disabled    boolean = false,
    sort_index  int = 0
) returns rule.action_reaction as
$$
    update rule.action_reaction
    set
        "trigger"=update_action_reaction."trigger",
        action_id=update_action_reaction.action_id,
        reaction_id=update_action_reaction.reaction_id,
        disabled=update_action_reaction.disabled,
        sort_index=update_action_reaction.sort_index,
        updated_by=private.current_user_id(),
        updated_at=now()
    where id = update_action_reaction.id
    returning *
$$
language sql volatile;

----

create function rule.delete_action_reaction(
    id          uuid
) returns rule.action_reaction as
$$
    delete from rule.action_reaction
    where id = delete_action_reaction.id
    returning *
$$
language sql volatile;

----

create function rule.action_reaction_full_name(
    action_reaction rule.action_reaction
) returns text as $$
    select (select name from rule.action where id = action_reaction.action_id) || ' -> ' || (select name from rule.reaction where id = action_reaction.reaction_id)
$$ language sql stable;

comment on function rule.action_reaction_full_name is '@notNull';
