create table public.pain008_mandate (
    id uuid primary key default uuid_generate_v4(),

    partner_company_id uuid not null unique references public.partner_company(id) on delete cascade,

    -- if null, use id with stripped dashes
    mandate_id trimmed_text not null,

    -- if null, inherit from partner
    debtor_name trimmed_text,
    debtor_iban public.bank_iban not null,
    debtor_bic  public.bank_bic,

    -- if null, use invoice date
    signature_date date,

    updated_at updated_time not null,
    created_at created_time not null
);

create index pain008_mandate_partner_company_id_idx on public.pain008_mandate (partner_company_id);

grant select, insert, update on table public.pain008_mandate to domonda_user;
grant select on public.pain008_mandate to domonda_wg_user;

create function public.upsert_pain008_mandate(
    partner_company_id uuid,
    mandate_id trimmed_text,
    debtor_iban public.bank_iban,
    debtor_bic public.bank_bic = null,
    debtor_name trimmed_text = null,
    signature_date date = null
) returns public.pain008_mandate as $$
    insert into public.pain008_mandate (
        partner_company_id,
        mandate_id,
        debtor_iban,
        debtor_bic,
        debtor_name,
        signature_date
    ) values (
        upsert_pain008_mandate.partner_company_id,
        upsert_pain008_mandate.mandate_id,
        upsert_pain008_mandate.debtor_iban,
        upsert_pain008_mandate.debtor_bic,
        upsert_pain008_mandate.debtor_name,
        upsert_pain008_mandate.signature_date
    )
    on conflict (partner_company_id) do update set
        mandate_id=upsert_pain008_mandate.mandate_id,
        debtor_iban=upsert_pain008_mandate.debtor_iban,
        debtor_bic=upsert_pain008_mandate.debtor_bic,
        debtor_name=upsert_pain008_mandate.debtor_name,
        signature_date=upsert_pain008_mandate.signature_date,
        updated_at=now()
    returning *
$$ language sql volatile;

----

create type public.pain008_local_instrument_code as enum (
    'CORE',
    'B2B'
);

create table public.pain008 (
    id uuid primary key default uuid_generate_v4(),

    bank_account_id uuid not null references public.bank_account(id) on delete restrict,
    collection_date date not null,

    local_instrument_code public.pain008_local_instrument_code not null,

    created_at created_time not null
);

-- inserted by the backend
grant select on table public.pain008 to domonda_user;
grant select on public.pain008 to domonda_wg_user;

create table public.pain008_payment (
    id uuid primary key default uuid_generate_v4(),

    pain008_id uuid not null references public.pain008(id) on delete cascade,

    -- TODO: should be made sure that the mandate partner is the invoice partner
    pain008_mandate_id  uuid not null references public.pain008_mandate(id) on delete restrict,
    invoice_document_id uuid references public.invoice(document_id) on delete set null,

    signature_date  date not null,

    amount   float8 not null,
    currency public.currency_code not null,

    purpose text not null,

    created_at created_time not null
);

create index pain008_payment_pain008_id_idx on public.pain008_payment (pain008_id);
create index pain008_payment_pain008_mandate_id_idx on public.pain008_payment (pain008_mandate_id);
create index pain008_payment_invoice_document_id_idx on public.pain008_payment (invoice_document_id);

-- inserted by the backend
grant select on table public.pain008_payment to domonda_user;
grant select on public.pain008_payment to domonda_wg_user;
