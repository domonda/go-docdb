create type public.finance_summary as (
    bank_balance_sum float8,
    assets           float8,
    liabilities      float8
);

-- public.finance_summary columns can be NULL because the user might not have bank accounts or any invoices

create function public.finance_summary(
    client_company_id uuid
) returns public.finance_summary as $$
    select
        -- balance
        (select sum(coalesce(balance, 0)) from public.bank_account where bank_account.client_company_id = finance_summary.client_company_id),
        -- assets
        sum(
            case
                when document_category.document_type = 'OUTGOING_INVOICE' and not invoice.credit_memo
                then coalesce(public.invoice_converted_total(invoice), 0)
                when document_category.document_type = 'OUTGOING_INVOICE' and invoice.credit_memo
                then coalesce(public.invoice_converted_total(invoice), 0) * -1
                else 0
            end
        ) as assets,
        -- liabilities
        sum(
            case
                when document_category.document_type = 'INCOMING_INVOICE' and not invoice.credit_memo
                then coalesce(public.invoice_converted_total(invoice), 0)
                when document_category.document_type = 'INCOMING_INVOICE' and invoice.credit_memo
                then coalesce(public.invoice_converted_total(invoice), 0) * -1
                else 0
            end
        ) as liabilities
    from private.filter_documents_v2(
        client_company_id=>finance_summary.client_company_id,
        superseded=>false,
        archived=>false,
        document_types=>'{OUTGOING_INVOICE,INCOMING_INVOICE}',
        paid_status=>'NOT_PAID'
    ) as document
        inner join public.document_category on document_category.id = document.category_id
        inner join public.invoice on invoice.document_id = document.id
$$ language sql stable strict security definer;

----

create type public.bank_transactions_stats as (
    "date"       timestamptz, -- truncated to month
    sum_incoming float8,
    sum_outgoing float8
);

comment on column public.bank_transactions_stats."date" is '@notNull';
comment on column public.bank_transactions_stats.sum_incoming is '@notNull';
comment on column public.bank_transactions_stats.sum_outgoing is '@notNull';

create function public.bank_transactions_stats(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.bank_transactions_stats as $$
    select
        -- date (truncated to month)
        date_trunc('month', bank_transaction.booking_date)::timestamptz as "date",
        -- sum_incoming
        sum(case when bank_transaction."type" = 'INCOMING' then bank_transaction.amount else 0 end) as sum_incoming,
        -- sum_outgoing
        sum(case when bank_transaction."type" = 'OUTGOING' then bank_transaction.amount else 0 end) as sum_outgoing
    from public.bank_transaction
        inner join public.bank_account on bank_account.id = bank_transaction.account_id
    where bank_account.client_company_id = bank_transactions_stats.client_company_id
    and bank_transaction.booking_date >= coalesce(bank_transactions_stats.from_date, current_date - interval '1 year')
    and bank_transaction.booking_date <= coalesce(bank_transactions_stats.until_date, current_date)
    -- partner of the transaction is not from an account belonging to the same client
    and (bank_transaction.partner_iban is null
        or not exists (select from public.bank_account
            where bank_account.client_company_id = bank_transactions_stats.client_company_id
            and bank_account.iban = bank_transaction.partner_iban))
    group by "date"
    order by "date"
$$ language sql stable security definer;

comment on function public.bank_transactions_stats is 'Statistics about `BankTransactions`. If no date range is given, it looks 1 year back.';

----

create type public.partner_stats as (
    partner_company_id uuid,
    partner_name       text,
    total_sum          float8,
    net_sum            float8
);

comment on column public.partner_stats.partner_company_id is '@notNull';
comment on column public.partner_stats.total_sum is '@notNull';
comment on column public.partner_stats.net_sum is '@notNull';
comment on type public.partner_stats is $$
@primaryKey partner_company_id
@foreignKey (partner_company_id) references public.partner_company (id)$$;

create function public.partner_stats(
    client_company_id uuid,
    "type"            public.partner_account_type,
    from_date         date = null,
    until_date        date = null
) returns setof public.partner_stats as $$
    select
        invoice.partner_company_id as partner_company_id,
        public.invoice_partner_name(invoice) as partner_name,
        sum(coalesce(public.invoice_converted_total(invoice), 0) * case when invoice.credit_memo then -1 else 1 end) as total_sum,
        sum(coalesce(public.invoice_converted_net(invoice), 0) * case when invoice.credit_memo then -1 else 1 end) as net_sum
    from private.filter_documents_v2(
        client_company_id=>partner_stats.client_company_id,
        superseded=>false,
        -- archived=>false, need to be considered
        document_types=>'{OUTGOING_INVOICE,INCOMING_INVOICE}',
        date_filter_type=>'INVOICE_DATE',
        from_date=>coalesce(partner_stats.from_date, current_date - interval '1 year')::date, -- if date is not specified, look only a year back
        until_date=>partner_stats.until_date
    ) as document
        inner join public.document_category on document_category.id = document.category_id
        inner join public.invoice on invoice.document_id = document.id
    where invoice.partner_company_id is not null
    and (
        (partner_stats."type" = 'VENDOR'
            and document_category.document_type = 'INCOMING_INVOICE')
        or (partner_stats."type" = 'CLIENT'
            and document_category.document_type = 'OUTGOING_INVOICE')
    )
    group by partner_company_id, partner_name
    order by net_sum desc
$$ language sql stable security definer;
