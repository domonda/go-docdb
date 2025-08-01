create view api.accounting_instruction with (security_barrier) as
    select
        ai.id,
        ai.client_company_id,
        ai.instruction,
        ai.updated_by,
        ai.updated_at,
        ai.created_by,
        ai.created_at
    from public.accounting_instruction ai
    where ai.client_company_id = api.current_client_company_id();

grant select on table api.accounting_instruction to domonda_api;

comment on column api.accounting_instruction.id is '@notNull';
comment on column api.accounting_instruction.client_company_id is '@notNull';
comment on column api.accounting_instruction.instruction is '@notNull';
comment on column api.accounting_instruction.updated_by is '@notNull';
comment on column api.accounting_instruction.updated_at is '@notNull';
comment on column api.accounting_instruction.created_by is '@notNull';
comment on column api.accounting_instruction.created_at is '@notNull';

comment on view api.accounting_instruction is $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company(company_id)
@foreignKey (updated_by) references api.user(id)
@foreignKey (created_by) references api.user(id)
Accounting instructions for the current client company
$$;