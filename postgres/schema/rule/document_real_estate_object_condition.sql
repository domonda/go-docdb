create table rule.document_real_estate_object_condition (
    id uuid primary key default uuid_generate_v4(),

    action_id uuid not null references rule.action(id) on delete cascade,

    document_real_estate_object_instance_id_equality rule.equality_operator not null,
    document_real_estate_object_instance_id          uuid references object.instance(id) on delete cascade,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

grant all on rule.document_real_estate_object_condition to domonda_user;
grant select on rule.document_real_estate_object_condition to domonda_wg_user;

----

create function rule.document_real_estate_object_condition_real_estate_object(
    document_real_estate_object_condition rule.document_real_estate_object_condition
) returns public.real_estate_object as $$
    select * from public.real_estate_object
    where real_estate_object.id = document_real_estate_object_condition.document_real_estate_object_instance_id
$$ language sql stable strict;

----

create function rule.check_document_real_estate_object_condition_is_used()
returns trigger as $$
declare
    rec rule.document_real_estate_object_condition;
begin
    if TG_OP = 'DELETE' then
        rec = OLD;
    else
        rec = NEW;
    end if;

    if exists (select from rule.action_reaction
        where action_reaction.action_id = rec.action_id)
    and not rule.current_user_is_special()
    then
        raise exception 'Action is in use';
    end if;

    return rec;
end
$$ language plpgsql stable;

create trigger rule_check_document_real_estate_object_condition_is_used_trigger
    before insert or update or delete
    on rule.document_real_estate_object_condition
    for each row
    execute procedure rule.check_document_real_estate_object_condition_is_used();

----

create function rule.create_document_real_estate_object_condition (
    action_id                                        uuid,
    document_real_estate_object_instance_id_equality rule.equality_operator,
    document_real_estate_object_instance_id          uuid = null
) returns rule.document_real_estate_object_condition as
$$
    insert into rule.document_real_estate_object_condition (action_id, document_real_estate_object_instance_id_equality, document_real_estate_object_instance_id, created_by)
        values (create_document_real_estate_object_condition.action_id, create_document_real_estate_object_condition.document_real_estate_object_instance_id_equality, create_document_real_estate_object_condition.document_real_estate_object_instance_id, private.current_user_id())
    returning *
$$
language sql volatile;

create function rule.update_document_real_estate_object_condition (
    id                                               uuid,
    document_real_estate_object_instance_id_equality rule.equality_operator,
    document_real_estate_object_instance_id          uuid = null
) returns rule.document_real_estate_object_condition as
$$
    update rule.document_real_estate_object_condition
        set
            document_real_estate_object_instance_id_equality=update_document_real_estate_object_condition.document_real_estate_object_instance_id_equality,
            document_real_estate_object_instance_id=update_document_real_estate_object_condition.document_real_estate_object_instance_id,
            updated_by=private.current_user_id(),
            updated_at=now()
    where id = update_document_real_estate_object_condition.id
    returning *
$$
language sql volatile;

create function rule.delete_document_real_estate_object_condition (
    id uuid
) returns rule.document_real_estate_object_condition as
$$
    delete from rule.document_real_estate_object_condition
    where id = delete_document_real_estate_object_condition.id
    returning *
$$
language sql volatile strict;
