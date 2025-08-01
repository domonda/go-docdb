create table public.accounting_instruction (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    instruction trimmed_text not null,

    created_by uuid not null
        default public.unknown_user_id()
        references public.user(id) on delete set default,
    created_at timestamptz not null default now(),

    updated_by uuid not null
        default public.unknown_user_id()
        references public.user(id) on delete set default,
    updated_at timestamptz not null default now()
);

create index accounting_instruction_client_company_id_idx on public.accounting_instruction(client_company_id);

create function public.add_accounting_instruction(
    client_company_id uuid,
    instruction       trimmed_text,
    created_by        uuid = private.current_user_id()
) returns public.accounting_instruction as $$
    insert into public.accounting_instruction (
        client_company_id,
        instruction,
        created_by,
        updated_by
    ) values (
        add_accounting_instruction.client_company_id,
        add_accounting_instruction.instruction,
        add_accounting_instruction.created_by,
        add_accounting_instruction.created_by
    )
    returning *
$$ language sql volatile;

create function public.update_accounting_instruction(
    id          uuid,
    instruction trimmed_text,
    updated_by   uuid = private.current_user_id()
) returns public.accounting_instruction as $$
    update public.accounting_instruction set
        instruction = update_accounting_instruction.instruction,
        updated_by = update_accounting_instruction.updated_by,
        updated_at = now()
    where id = update_accounting_instruction.id
    returning *
$$ language sql volatile;

create function public.delete_accounting_instruction(
    id uuid
) returns public.accounting_instruction as $$
    delete from public.accounting_instruction
    where id = delete_accounting_instruction.id
    returning *
$$ language sql volatile;