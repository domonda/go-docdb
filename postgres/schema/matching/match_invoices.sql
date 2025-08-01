create function matching.match_invoices(
  invoice_document_ids uuid[]
) returns setof public.document_money_transaction as $$
declare
  prepared_invoice record;
  match record;
begin
  for prepared_invoice in (
    select
      invoice.document_id as document_id,
      document.client_company_id as client_company_id,
      public.invoice_converted_signed_total_with_payment_discount(invoice) as total,
      invoice.invoice_number as "number",
      invoice.order_number as order_number,
      invoice.invoice_date as "date",
      private.partner_company_all_names(partner_company) as partner_names,
      public.invoice_payment_iban(invoice) as partner_iban
    from public.invoice
      inner join (public.document
        inner join public.document_category on document_category.id = document.category_id)
      on document.id = invoice.document_id
      left join public.partner_company on partner_company.id = invoice.partner_company_id
    -- must be one of the invoices
    where invoice.document_id = any(match_invoices.invoice_document_ids)
    -- is either incoming or outgoing invoice
    and document_category.document_type in ('INCOMING_INVOICE', 'OUTGOING_INVOICE')
    -- the booking type is not a cash book
    and document_category.booking_type is distinct from 'CASH_BOOK'
    -- ignore superseded
    and not document.superseded
    -- ignore archived
    and not document.archived
    -- doesnt have an existing match
    and not exists (
      -- much faster then using the `document_money_transaction` view
      (
        select from public.document_bank_transaction as document_transaction
        where document_transaction.document_id = document.id
      ) union all (
        select from public.document_credit_card_transaction as document_transaction
        where document_transaction.document_id = document.id
      ) union all (
        select from public.document_cash_transaction as document_transaction
        where document_transaction.document_id = document.id
      ) union all (
        select from public.document_paypal_transaction as document_transaction
        where document_transaction.document_id = document.id
      ) union all (
        select from public.document_stripe_transaction as document_transaction
        where document_transaction.document_id = document.id
      )
    )
    -- invoice has a invoice date
    and invoice.invoice_date is not null
    -- invoice does not have a payment status or is payed with a matchable type or is partially paid
    and (
      invoice.payment_status is null
      or invoice.payment_status in ('CREDITCARD', 'BANK', 'PAYPAL', 'TRANSFERWISE', 'DIRECT_DEBIT')
      or invoice.partially_paid
    )
  )
  loop
    with prepared_money_transaction as (
      select
        money_transaction.id,
        money_account.client_company_id as client_company_id,
        (case money_account."type"
            when 'BANK_ACCOUNT' then 'BANK'
            else 'CREDIT_CARD'
        end)::matching.transaction_type as "type",
        public.money_transaction_signed_amount(money_transaction) as total,
        money_transaction.purpose as purpose,
        coalesce(money_transaction.value_date, money_transaction.booking_date)::date as "date",
        money_transaction.partner_name as partner_name,
        money_transaction.partner_iban as partner_iban
      from public.money_transaction
        inner join public.money_account on money_account.id = money_transaction.account_id
      -- must be from the invoice's client company
      where money_account.client_company_id = prepared_invoice.client_company_id
      -- transaction must have a reference/purpose
      and money_transaction.purpose is not null
      -- is not in a category
      and money_transaction.money_category_id is null
      -- is not already matched
      and not exists (
        -- much faster then using the `document_money_transaction` view
        (
          select from public.document_bank_transaction as document_transaction
          where document_transaction.bank_transaction_id = money_transaction.id
        ) union all (
          select from public.document_credit_card_transaction as document_transaction
          where document_transaction.credit_card_transaction_id = money_transaction.id
        ) union all (
          select from public.document_cash_transaction as document_transaction
          where document_transaction.cash_transaction_id = money_transaction.id
        ) union all (
          select from public.document_paypal_transaction as document_transaction
          where document_transaction.paypal_transaction_id = money_transaction.id
        ) union all (
          select from public.document_stripe_transaction as document_transaction
          where document_transaction.stripe_transaction_id = money_transaction.id
        )
      )
      -- invoice date must be at the transaction value/booking date or up to 28 days (4 weeks) in the future
      and date_part('day', coalesce(money_transaction.value_date, money_transaction.booking_date)::timestamptz - prepared_invoice."date"::timestamptz) >= -28
      -- invoice date must not be more than 120 days (4 months) before the transaction value/booking date
      and date_part('day', coalesce(money_transaction.value_date, money_transaction.booking_date)::timestamptz - prepared_invoice."date"::timestamptz) <= 120
      -- totals percentage difference shouldn't exceed 50%
      and abs(public.percent_difference_between_numbers(prepared_invoice.total, public.money_transaction_signed_amount(money_transaction))) <= 0.5
    )
    select
      prepared_invoice.document_id as invoice_document_id,
      prepared_money_transaction.id as money_transaction_id,
      match_check_id as check_id
    into match
    from
      prepared_money_transaction,
      matching.perform_checks(
        prepared_invoice.client_company_id,
        -- invoice
        prepared_invoice.total,
        prepared_invoice."number",
        prepared_invoice.order_number,
        prepared_invoice."date",
        prepared_invoice.partner_names,
        prepared_invoice.partner_iban,
        -- transaction
        prepared_money_transaction."type",
        prepared_money_transaction.total,
        prepared_money_transaction.purpose,
        prepared_money_transaction."date",
        prepared_money_transaction.partner_name,
        prepared_money_transaction.partner_iban
      ) as match_check_id
        left join lateral (
          select client_company_rule_check.* from matching.client_company_rule_check
            inner join matching.client_company_rule on client_company_rule.id = client_company_rule_check.rule_id
          where client_company_rule_check.check_id = match_check_id
          and (client_company_rule.client_company_id = prepared_invoice.client_company_id
            or client_company_rule.client_company_id is null)
          order by client_company_rule.client_company_id nulls last -- prefer focused matching rules
          limit 1
        ) client_company_rule_check on true
    -- is a match
    where match_check_id is not null
    order by
      -- check priority
      client_company_rule_check.priority desc,
      -- then total percent difference
      abs(public.percent_difference_between_numbers(prepared_invoice.total, prepared_money_transaction.total)) asc,
      -- then date day distance
      abs(date_part('day', prepared_money_transaction."date"::timestamptz - prepared_invoice."date"::timestamptz)) asc
    -- single matches only
    limit 1;

    case
      when exists (select from public.bank_transaction where id = match.money_transaction_id)
      then
        insert into public.document_bank_transaction (document_id, bank_transaction_id, check_id)
        values (match.invoice_document_id, match.money_transaction_id, match.check_id);
      when exists (select from public.credit_card_transaction where id = match.money_transaction_id)
      then
        insert into public.document_credit_card_transaction (document_id, credit_card_transaction_id, check_id)
        values (match.invoice_document_id, match.money_transaction_id, match.check_id);
      when exists (select from public.cash_transaction where id = match.money_transaction_id)
      then
        insert into public.document_cash_transaction (document_id, cash_transaction_id, check_id)
        values (match.invoice_document_id, match.money_transaction_id, match.check_id);
      when exists (select from public.paypal_transaction where id = match.money_transaction_id)
      then
        insert into public.document_paypal_transaction (document_id, paypal_transaction_id, check_id)
        values (match.invoice_document_id, match.money_transaction_id, match.check_id);
      when exists (select from public.stripe_transaction where id = match.money_transaction_id)
      then
        insert into public.document_stripe_transaction (document_id, stripe_transaction_id, check_id)
        values (match.invoice_document_id, match.money_transaction_id, match.check_id);
      else
        continue;
    end case;

    return query (
      select * from public.document_money_transaction
      where document_money_transaction.document_id = match.invoice_document_id
      and document_money_transaction.money_transaction_id = match.money_transaction_id
    );
  end loop;
end
$$ language plpgsql volatile;
comment on function matching.match_invoices is '@omit';
