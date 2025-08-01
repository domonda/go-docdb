create type rule.document_condition_payment_status as enum (
    'PAID',
    -- public.document_payment_status
    'NOT_PAYABLE',
    'NOT_PAID',
    'PARTIALLY_PAID',
    'PAID_WITH_BANK',
    'PAID_WITH_CREDITCARD',
    'PAID_WITH_CASH',
    'PAID_WITH_PAYPAL',
    'PAID_WITH_TRANSFERWISE',
    'PAID_WITH_DIRECT_DEBIT',
    'EXPENSES_PAID'
);

-- no primary key because there can be only one document_condition
-- NOTE: document_condition without checks passes ALL documents
create table rule.document_condition (
    action_id uuid primary key references rule.action(id) on delete cascade,

    approved boolean, -- null means we don't care

    has_controller_user_on_document_partner_company boolean, -- null means we dont care

    payment_status rule.document_condition_payment_status, -- null means we dont care

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    created_at created_time NOT NULL,
    updated_at updated_time NOT NULL
);

grant all on rule.document_condition to domonda_user;
grant select on rule.document_condition to domonda_wg_user;

create index rule_document_condition_action_id_idx on rule.document_condition (action_id);

----

create function rule.check_document_condition_is_used()
returns trigger as $$
declare
    rec rule.document_condition;
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

create trigger rule_check_document_condition_is_used_trigger
    before insert or update or delete
    on rule.document_condition
    for each row
    execute procedure rule.check_document_condition_is_used();

----

create function rule.create_document_condition (
    action_id uuid,
    approved  boolean = null,
    has_controller_user_on_document_partner_company boolean = null,
    payment_status rule.document_condition_payment_status = null
) returns rule.document_condition as
$$
    insert into rule.document_condition (action_id, approved, created_by, has_controller_user_on_document_partner_company, payment_status)
    values (
        create_document_condition.action_id,
        create_document_condition.approved,
        private.current_user_id(),
        create_document_condition.has_controller_user_on_document_partner_company,
        create_document_condition.payment_status
    )
    returning *
$$
language sql volatile;

----

create function rule.update_document_condition (
    action_id uuid,
    approved  boolean = null,
    has_controller_user_on_document_partner_company boolean = null,
    payment_status rule.document_condition_payment_status = null
) returns rule.document_condition as
$$
    update rule.document_condition
    set
        approved=update_document_condition.approved,
        has_controller_user_on_document_partner_company=update_document_condition.has_controller_user_on_document_partner_company,
        payment_status=update_document_condition.payment_status,
        updated_by=private.current_user_id(),
        updated_at=now()
    where action_id = update_document_condition.action_id
    returning *
$$
language sql volatile;

----

create function rule.delete_document_condition (
    action_id uuid
) returns rule.document_condition as
$$
    delete from rule.document_condition
    where action_id = delete_document_condition.action_id
    returning *
$$
language sql volatile strict;
