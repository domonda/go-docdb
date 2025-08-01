create table rule.document_import_date_condition (
    id uuid primary key default uuid_generate_v4(),

    action_id uuid not null references rule.action(id) on delete cascade,

    import_date_comparison rule.comparison_operator not null,
    import_date            date,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time not null,
    created_at created_time not null
);

grant all on rule.document_import_date_condition to domonda_user;
grant select on rule.document_import_date_condition to domonda_wg_user;

create unique index rule_document_import_date_condition_unique on rule.document_import_date_condition (action_id, import_date);
create unique index rule_document_import_date_condition_unique_null on rule.document_import_date_condition (action_id) where (import_date is null);

create index rule_document_import_date_condition_action_id_idx on rule.document_import_date_condition (action_id);

----

create function rule.check_document_import_date_condition_is_used()
returns trigger as $$
declare
    rec rule.document_import_date_condition;
begin
    if TG_OP = 'DELETE' then
        rec = OLD;
    else
        rec = NEW;
    end if;

    if exists (select from rule.action_reaction where action_reaction.action_id = rec.action_id)
        and not rule.current_user_is_special()
    then
        raise exception 'Action is in use';
    end if;

    return rec;
end
$$ language plpgsql stable;

create trigger rule_check_document_import_date_condition_is_used_trigger
    before insert or update or delete
    on rule.document_import_date_condition
    for each row
    execute procedure rule.check_document_import_date_condition_is_used();

----

create function rule.create_document_import_date_condition (
    action_id              uuid,
    import_date_comparison rule.comparison_operator,
    import_date            date = null
) returns rule.document_import_date_condition as
$$
    insert into rule.document_import_date_condition (action_id, import_date_comparison, import_date, created_by)
        values (create_document_import_date_condition.action_id, create_document_import_date_condition.import_date_comparison, create_document_import_date_condition.import_date, private.current_user_id())
    returning *
$$
language sql volatile;

----

create function rule.update_document_import_date_condition (
    id                     uuid,
    import_date_comparison rule.comparison_operator,
    import_date            date = null
) returns rule.document_import_date_condition as
$$
    update rule.document_import_date_condition
    set
        import_date_comparison=update_document_import_date_condition.import_date_comparison,
        import_date=update_document_import_date_condition.import_date,
        updated_by=private.current_user_id(),
        updated_at=now()
    where id = update_document_import_date_condition.id
    returning *
$$
language sql volatile;

----

create function rule.delete_document_import_date_condition (
    id uuid
) returns rule.document_import_date_condition as
$$
    delete from rule.document_import_date_condition
    where id = delete_document_import_date_condition.id
    returning *
$$
language sql volatile strict;
