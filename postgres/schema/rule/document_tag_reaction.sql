create table rule.document_tag_reaction (
    reaction_id uuid primary key references rule.reaction(id) on delete cascade,

    client_company_tag_id uuid not null references public.client_company_tag(id) on delete cascade,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time not null,
    created_at created_time not null
);

grant all on rule.document_tag_reaction to domonda_user;
grant select on rule.document_tag_reaction to domonda_wg_user;

----

create function rule.check_document_tag_reaction_is_used()
returns trigger as $$
declare
    rec rule.document_tag_reaction;
begin
    if tg_op = 'DELETE' then
        rec = old;
    else
        rec = new;
    end if;

    if exists (select from rule.action_reaction where action_reaction.reaction_id = rec.reaction_id)
        and not rule.current_user_is_special()
    then
        raise exception 'Reaction is in use';
    end if;

    return rec;
end
$$ language plpgsql stable;

create trigger rule_check_document_tag_reaction_is_used_trigger
    before insert or update or delete
    on rule.document_tag_reaction
    for each row
    execute procedure rule.check_document_tag_reaction_is_used();

----

create function rule.create_document_tag_reaction(
    reaction_id           uuid,
    client_company_tag_id uuid
) returns rule.document_tag_reaction as
$$
    insert into rule.document_tag_reaction (
        reaction_id,
        client_company_tag_id,
        created_by
    ) values (
        create_document_tag_reaction.reaction_id,
        create_document_tag_reaction.client_company_tag_id,
        private.current_user_id()
    )
    returning *
$$
language sql volatile;

----

create function rule.update_document_tag_reaction(
    reaction_id           uuid,
    client_company_tag_id uuid
) returns rule.document_tag_reaction as
$$
    update rule.document_tag_reaction
        set
            client_company_tag_id=update_document_tag_reaction.client_company_tag_id,
            updated_by=private.current_user_id(),
            updated_at=now()
    where reaction_id = update_document_tag_reaction.reaction_id
    returning *
$$
language sql volatile;

----

create function rule.delete_document_tag_reaction(
    reaction_id uuid
) returns rule.document_tag_reaction as
$$
    delete from rule.document_tag_reaction
    where reaction_id = delete_document_tag_reaction.reaction_id
    returning *
$$
language sql volatile strict;

----

create function rule.do_document_tag_reaction(
    document_tag_reaction rule.document_tag_reaction,
    document              public.document
) returns void as
$$
begin
    insert into public.document_tag (client_company_tag_id, document_id)
    values (
        document_tag_reaction.client_company_tag_id,
        document.id
    )
    on conflict(client_company_tag_id, document_id)
        do update set updated_at=now();
end
$$
language plpgsql volatile strict;

comment on function rule.do_document_tag_reaction is '@omit';

----

create function rule.do_document_tag_action_reaction(
    action_reaction rule.action_reaction,
    document        public.document
) returns void as
$$
declare
    document_tag_reaction rule.document_tag_reaction;
begin
    if action_reaction."trigger" in ('ALWAYS', 'ONCE', 'DOCUMENT_CHANGED')
        and exists(
            select from rule.document_tag_log
            where document_tag_log.action_reaction_id = action_reaction.id
            and document_tag_log.document_id = document.id
            and (action_reaction."trigger" = 'ONCE'
                -- some triggers should not execute multiple times recursively
                or document_tag_log.created_at = now()
            )
        )
    then
        return;
    end if;

    -- find reaction
    select
        * into document_tag_reaction
    from rule.document_tag_reaction where reaction_id = action_reaction.reaction_id;

    -- if there is no reaction, return
    if document_tag_reaction is null then
        return;
    end if;

    -- react
    perform rule.do_document_tag_reaction(document_tag_reaction, document);

    -- log
    insert into rule.document_tag_log (action_reaction_id, document_id)
    values (action_reaction.id, document.id);
end
$$
language plpgsql volatile;

comment on function rule.do_document_tag_action_reaction is '@omit';
