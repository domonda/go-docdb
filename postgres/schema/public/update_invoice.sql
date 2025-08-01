CREATE TYPE private.invoice_value_fields AS (
  val 		text,
  conf_by text,
  conf_at timestamptz
);

CREATE FUNCTION private.calc_invoice_value_fields(
  new_val     text,
  old_val     text,
  conf_by_old text,
  conf_at_old timestamptz
) RETURNS private.invoice_value_fields AS
$$
DECLARE
  inv_val_flds private.invoice_value_fields;
BEGIN
  -- NOTE: we coalesce here because `null` compared to any value is `null`!
  IF COALESCE(calc_invoice_value_fields.old_val, '') = COALESCE(calc_invoice_value_fields.new_val, '') THEN

    -- don't update because the value didn't changed
    inv_val_flds.val := calc_invoice_value_fields.old_val;
    inv_val_flds.conf_by := calc_invoice_value_fields.conf_by_old;
    inv_val_flds.conf_at := calc_invoice_value_fields.conf_at_old;

  ELSE

    -- update because the value changed
    inv_val_flds.val := calc_invoice_value_fields.new_val;
    inv_val_flds.conf_by := (SELECT id FROM private.current_user());
    inv_val_flds.conf_at := now();

  END IF;

  RETURN inv_val_flds;
END;
$$
LANGUAGE plpgsql VOLATILE;

----

CREATE TYPE private.invoice_conversion_rate_fields AS (
  conversion_rate        float8,
  conversion_rate_date   date,
  conversion_rate_source text
);

CREATE FUNCTION private.calc_invoice_conversion_rate_fields(
  currency                   public.currency_code,
  invoice_date               date,
  new_conversion_rate        float8,
  old_conversion_rate        float8,
  old_conversion_rate_date   date,
  old_conversion_rate_source text
) RETURNS private.invoice_conversion_rate_fields AS
$$
DECLARE
  conv_rat_inv_val_flds   private.invoice_conversion_rate_fields;
  looked_up_currency_rate RECORD;
BEGIN
  -- no conversion rate for EUR currency
  IF calc_invoice_conversion_rate_fields.currency = 'EUR' THEN

    conv_rat_inv_val_flds.conversion_rate = NULL;
    conv_rat_inv_val_flds.conversion_rate_date = NULL;
    conv_rat_inv_val_flds.conversion_rate_source = NULL;

    RETURN conv_rat_inv_val_flds;

  END IF;

  -- user changed the conversion rate
  IF calc_invoice_conversion_rate_fields.new_conversion_rate IS DISTINCT FROM calc_invoice_conversion_rate_fields.old_conversion_rate THEN

    conv_rat_inv_val_flds.conversion_rate = calc_invoice_conversion_rate_fields.new_conversion_rate;
    conv_rat_inv_val_flds.conversion_rate_date = now();
    conv_rat_inv_val_flds.conversion_rate_source = (SELECT id FROM private.current_user());

    RETURN conv_rat_inv_val_flds;

  END IF;

  -- user did not change the conversion rate

  -- previous conversion rate change was done by a user, return old values
  IF public.uuid_or_null(calc_invoice_conversion_rate_fields.old_conversion_rate_source) IS NOT NULL THEN

    conv_rat_inv_val_flds.conversion_rate = calc_invoice_conversion_rate_fields.old_conversion_rate;
    conv_rat_inv_val_flds.conversion_rate_date = calc_invoice_conversion_rate_fields.old_conversion_rate_date;
    conv_rat_inv_val_flds.conversion_rate_source = calc_invoice_conversion_rate_fields.old_conversion_rate_source;

    RETURN conv_rat_inv_val_flds;

  END IF;

  -- invoice date is null, unable to lookup the currency rate. nullify everything
  IF calc_invoice_conversion_rate_fields.invoice_date IS NULL THEN

    conv_rat_inv_val_flds.conversion_rate = NULL;
    conv_rat_inv_val_flds.conversion_rate_date = NULL;
    conv_rat_inv_val_flds.conversion_rate_source = NULL;

    RETURN conv_rat_inv_val_flds;

  END IF;

  -- invoice date exists, lookup currency rate table
  SELECT
    cr.* INTO looked_up_currency_rate
  FROM public.currency_rate AS cr
  WHERE (
    cr."date" = calc_invoice_conversion_rate_fields.invoice_date
  ) AND (
    cr.currency = calc_invoice_conversion_rate_fields.currency
  );

  -- set looked up currency rate. if it was not found, set all fields to null
  conv_rat_inv_val_flds.conversion_rate = looked_up_currency_rate.rate;
  conv_rat_inv_val_flds.conversion_rate_date = looked_up_currency_rate."date";
  IF NOT (looked_up_currency_rate IS NULL) THEN
    conv_rat_inv_val_flds.conversion_rate_source = 'DATABASE_LOOKUP';
  ELSE
    conv_rat_inv_val_flds.conversion_rate_source = NULL;
  END IF;

  RETURN conv_rat_inv_val_flds;
END;
$$
LANGUAGE plpgsql VOLATILE;

----

CREATE FUNCTION private.update_invoice(
  document_id uuid,
  -- fields
  invoice_number              text,
  order_number                text,
  internal_number             text,
  invoice_date                date,
  order_date                  date,
  due_date                    date,
  paid_date                   date,
  payment_status              public.invoice_payment_status,
  net                         float8,
  total                       float8,
  currency                    public.currency_code,
  partner_company_id          uuid,
  partner_company_location_id uuid,
  iban                        public.bank_iban,
  bic                         public.bank_bic,
  payment_reference           text,
  credit_memo                 boolean,
  credit_memo_for_invoice_document_id uuid,
  discount_percent            float8,
  discount_amount             float8,
  discount_until              date,
  delivered_from              date,
  delivered_until             date,
  conversion_rate             float8,
  partially_paid              boolean,
  recurring                   boolean,
  recurring_interval          public.document_recurrence_interval,
  recurring_max_recurrences   int,
  recurring_ends_at           date,
  ger_clause_35a_net          float8,
  ger_clause_35a_total        float8,
  ger_clause_35a_kind         public.ger_clause_35a_kind
) RETURNS public.invoice AS
$$
declare
  next_invoice public.invoice;
begin
  UPDATE public.invoice
    SET
      -- invoice_number
      (invoice_number, invoice_number_confirmed_by, invoice_number_confirmed_at) = (
        SELECT * FROM private.calc_invoice_value_fields(
          update_invoice.invoice_number,
          invoice.invoice_number,
          invoice.invoice_number_confirmed_by,
          invoice.invoice_number_confirmed_at
        )
      ),
      -- order_number
      (order_number, order_number_confirmed_by, order_number_confirmed_at) = (
        SELECT * FROM private.calc_invoice_value_fields(
          update_invoice.order_number,
          invoice.order_number,
          invoice.order_number_confirmed_by,
          invoice.order_number_confirmed_at
        )
      ),
      -- internal_number
      (internal_number, internal_number_confirmed_by, internal_number_confirmed_at) = (
        SELECT * FROM private.calc_invoice_value_fields(
          update_invoice.internal_number,
          invoice.internal_number,
          invoice.internal_number_confirmed_by,
          invoice.internal_number_confirmed_at
        )
      ),
      -- invoice_date
      (invoice_date, invoice_date_confirmed_by, invoice_date_confirmed_at) = (
        SELECT val::date, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.invoice_date::text,
          invoice.invoice_date::text,
          invoice.invoice_date_confirmed_by,
          invoice.invoice_date_confirmed_at
        )
      ),
      -- order_date
      (order_date, order_date_confirmed_by, order_date_confirmed_at) = (
        SELECT val::date, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.order_date::text,
          invoice.order_date::text,
          invoice.order_date_confirmed_by,
          invoice.order_date_confirmed_at
        )
      ),
      -- due_date
      (due_date, due_date_confirmed_by, due_date_confirmed_at) = (
        SELECT val::date, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.due_date::text,
          invoice.due_date::text,
          invoice.due_date_confirmed_by,
          invoice.due_date_confirmed_at
        )
      ),
      -- paid_date
      (paid_date, paid_date_confirmed_by, paid_date_confirmed_at) = (
        SELECT val::date, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.paid_date::text,
          invoice.paid_date::text,
          invoice.paid_date_confirmed_by,
          invoice.paid_date_confirmed_at
        )
      ),
      -- payment_status
      (payment_status, payment_status_confirmed_by, payment_status_confirmed_at) = (
        SELECT val::public.invoice_payment_status, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.payment_status::text,
          invoice.payment_status::text,
          invoice.payment_status_confirmed_by,
          invoice.payment_status_confirmed_at
        )
      ),
      -- net
      (net, net_confirmed_by, net_confirmed_at) = (
        SELECT val::float8, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.net::text,
          invoice.net::text,
          invoice.net_confirmed_by,
          invoice.net_confirmed_at
        )
      ),
      -- total
      (total, total_confirmed_by, total_confirmed_at) = (
        SELECT val::float8, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.total::text,
          invoice.total::text,
          invoice.total_confirmed_by,
          invoice.total_confirmed_at
        )
      ),
      -- currency
      (currency, currency_confirmed_by, currency_confirmed_at) = (
        SELECT val::public.currency_code, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.currency::text,
          invoice.currency::text,
          invoice.currency_confirmed_by,
          invoice.currency_confirmed_at
        )
      ),
      -- partner_company_id
      (partner_company_id, partner_company_id_confirmed_by, partner_company_id_confirmed_at) = (
      	SELECT val::uuid, conf_by, conf_at FROM private.calc_invoice_value_fields(
      		update_invoice.partner_company_id::text,
      		invoice.partner_company_id::text,
      		invoice.partner_company_id_confirmed_by,
      		invoice.partner_company_id_confirmed_at
      	)
      ),
      -- partner_company_location_id
      (partner_company_location_id, partner_company_location_id_confirmed_by, partner_company_location_id_confirmed_at) = (
      	SELECT val::uuid, conf_by, conf_at FROM private.calc_invoice_value_fields(
      		update_invoice.partner_company_location_id::text,
      		invoice.partner_company_location_id::text,
      		invoice.partner_company_location_id_confirmed_by,
      		invoice.partner_company_location_id_confirmed_at
      	)
      ),
      -- iban
      (iban, iban_confirmed_by, iban_confirmed_at) = (
        SELECT val::public.bank_iban, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.iban,
          invoice.iban,
          invoice.iban_confirmed_by,
          invoice.iban_confirmed_at
        )
      ),
      -- bic
      (bic, bic_confirmed_by, bic_confirmed_at) = (
        SELECT val::public.bank_bic, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.bic,
          invoice.bic,
          invoice.bic_confirmed_by,
          invoice.bic_confirmed_at
        )
      ),
      -- payment_reference
      (payment_reference, payment_reference_confirmed_by, payment_reference_confirmed_at) = (
        SELECT val::text, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.payment_reference,
          invoice.payment_reference,
          invoice.payment_reference_confirmed_by,
          invoice.payment_reference_confirmed_at
        )
      ),
      -- credit_memo
      (credit_memo, credit_memo_confirmed_by, credit_memo_confirmed_at) = (
        SELECT val::boolean, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.credit_memo::text,
          invoice.credit_memo::text,
          invoice.credit_memo_confirmed_by,
          invoice.credit_memo_confirmed_at
        )
      ),
      -- credit_memo_for_invoice_document_id
      (credit_memo_for_invoice_document_id, credit_memo_for_invoice_document_id_confirmed_by, credit_memo_for_invoice_document_id_confirmed_at) = (
      	SELECT val::uuid, conf_by, conf_at FROM private.calc_invoice_value_fields(
      		update_invoice.credit_memo_for_invoice_document_id::text,
      		invoice.credit_memo_for_invoice_document_id::text,
      		invoice.credit_memo_for_invoice_document_id_confirmed_by,
      		invoice.credit_memo_for_invoice_document_id_confirmed_at
      	)
      ),
      -- discount_percent
      (discount_percent, discount_percent_confirmed_by, discount_percent_confirmed_at) = (
        SELECT val::float8, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.discount_percent::text,
          invoice.discount_percent::text,
          invoice.discount_percent_confirmed_by,
          invoice.discount_percent_confirmed_at
        )
      ),
      -- discount_amount
      (discount_amount, discount_amount_confirmed_by, discount_amount_confirmed_at) = (
        SELECT val::float8, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.discount_amount::text,
          invoice.discount_amount::text,
          invoice.discount_amount_confirmed_by,
          invoice.discount_amount_confirmed_at
        )
      ),
      -- discount_until
      (discount_until, discount_until_confirmed_by, discount_until_confirmed_at) = (
        SELECT val::date, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.discount_until::text,
          invoice.discount_until::text,
          invoice.discount_until_confirmed_by,
          invoice.discount_until_confirmed_at
        )
      ),
      -- delivered_from
      (delivered_from, delivered_from_confirmed_by, delivered_from_confirmed_at) = (
        SELECT val::date, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.delivered_from::text,
          invoice.delivered_from::text,
          invoice.delivered_from_confirmed_by,
          invoice.delivered_from_confirmed_at
        )
      ),
      -- delivered_until
      (delivered_until, delivered_until_confirmed_by, delivered_until_confirmed_at) = (
        SELECT val::date, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.delivered_until::text,
          invoice.delivered_until::text,
          invoice.delivered_until_confirmed_by,
          invoice.delivered_until_confirmed_at
        )
      ),
      -- conversion_rate
      (conversion_rate, conversion_rate_date, conversion_rate_source) = (
        SELECT * FROM private.calc_invoice_conversion_rate_fields(
          update_invoice.currency,
          update_invoice.invoice_date,
          update_invoice.conversion_rate::float8,
          invoice.conversion_rate::float8,
          invoice.conversion_rate_date::date,
          invoice.conversion_rate_source
        )
      ),
      -- partially_paid
      (partially_paid, partially_paid_confirmed_by, partially_paid_confirmed_at) = (
        SELECT val::boolean, conf_by::uuid, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.partially_paid::text,
          invoice.partially_paid::text,
          invoice.partially_paid_confirmed_by::text,
          invoice.partially_paid_confirmed_at
        )
      ),
      -- ger_clause_35a_net
      (ger_clause_35a_net, ger_clause_35a_net_confirmed_by, ger_clause_35a_net_confirmed_at) = (
        SELECT val::float8, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.ger_clause_35a_net::text,
          invoice.ger_clause_35a_net::text,
          invoice.ger_clause_35a_net_confirmed_by,
          invoice.ger_clause_35a_net_confirmed_at
        )
      ),
      -- ger_clause_35a_total
      (ger_clause_35a_total, ger_clause_35a_total_confirmed_by, ger_clause_35a_total_confirmed_at) = (
        SELECT val::float8, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.ger_clause_35a_total::text,
          invoice.ger_clause_35a_total::text,
          invoice.ger_clause_35a_total_confirmed_by,
          invoice.ger_clause_35a_total_confirmed_at
        )
      ),
      -- ger_clause_35a_kind
      (ger_clause_35a_kind, ger_clause_35a_kind_confirmed_by, ger_clause_35a_kind_confirmed_at) = (
        SELECT val::public.ger_clause_35a_kind, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice.ger_clause_35a_kind::text,
          invoice.ger_clause_35a_kind::text,
          invoice.ger_clause_35a_kind_confirmed_by,
          invoice.ger_clause_35a_kind_confirmed_at
        )
      ),
      updated_at=now()
  WHERE (invoice.document_id = update_invoice.document_id)
  RETURNING * INTO next_invoice;

  if recurring
  then
    perform public.set_document_recurrence(
      next_invoice.document_id,
      public.first_recurrence_date(next_invoice.invoice_date, update_invoice.recurring_interval),
      update_invoice.recurring_interval,
      update_invoice.recurring_max_recurrences,
      update_invoice.recurring_ends_at
    );
  end if;

  if recurring is not distinct from false
  then
    perform public.disable_active_document_recurrences(next_invoice.document_id);
  end if;

  -- recurring=null means no action whatsoever

  return next_invoice;
end
$$
LANGUAGE plpgsql VOLATILE;

----

CREATE FUNCTION public.update_invoice(
  document_id uuid,
  -- fields
  invoice_number              text = NULL,
  order_number                text = NULL,
  internal_number             text = NULL,
  invoice_date                date = NULL,
  order_date                  date = NULL,
  due_date                    date = NULL,
  paid_date                   date = NULL,
  payment_status              public.invoice_payment_status = NULL,
  net                         float8 = NULL,
  total                       float8 = NULL,
  currency                    public.currency_code = NULL,
  partner_company_id          uuid = NULL,
  partner_company_location_id uuid = NULL,
  iban                        public.bank_iban = NULL,
  bic                         public.bank_bic = NULL,
  payment_reference           text = NULL,
  credit_memo                 boolean = NULL,
  credit_memo_for_invoice_document_id uuid = NULL,
  discount_percent            float8 = NULL,
  discount_amount             float8 = NULL,
  discount_until              date = NULL,
  delivered_from              date = NULL,
  delivered_until             date = NULL,
  conversion_rate             float8 = NULL,
  partially_paid              boolean = false,
  recurring                   boolean = NULL,
  recurring_interval          public.document_recurrence_interval = NULL,
  recurring_max_recurrences   int = NULL,
  recurring_ends_at           date = NULL,
  ger_clause_35a_net          float8 = null,
  ger_clause_35a_total        float8 = null,
  ger_clause_35a_kind         public.ger_clause_35a_kind = null
) RETURNS public.invoice AS
$$
DECLARE
    result RECORD;
BEGIN
  result := private.update_invoice(
    document_id,
    invoice_number,
    order_number,
    internal_number,
    invoice_date,
    order_date,
    due_date,
    paid_date,
    payment_status,
    net,
    total,
    currency,
    partner_company_id,
    partner_company_location_id,
    iban,
    bic,
    payment_reference,
    credit_memo,
    credit_memo_for_invoice_document_id,
    discount_percent,
    discount_amount,
    discount_until,
    delivered_from,
    delivered_until,
    conversion_rate,
    partially_paid,
    recurring,
    recurring_interval,
    recurring_max_recurrences,
    recurring_ends_at,
    ger_clause_35a_net,
    ger_clause_35a_total,
    ger_clause_35a_kind
  );

  -- try auto-generating an accounting item on each invoice update
  if (select public.has_client_company_an_accounting_system(document.client_company_id)
    from public.document
    where document.id = result.document_id)
  and result.partner_company_id is not null
  and result.total is not null
  and result.total <> 0
  and not exists (
    select from public.invoice_accounting_item
    where invoice_accounting_item.invoice_document_id = result.document_id
    and (
      invoice_accounting_item.created_by != 'a77649b5-ff6d-4e87-a17c-23df3b2cad71' -- Accounting Suggester -- TODO use immutable function instead of UUID literal
      or invoice_accounting_item.updated_by is not null
    )
  )
  and not exists (
    select from public.invoice_accounting_item_cost_center
    join public.invoice_accounting_item on invoice_accounting_item.id = invoice_accounting_item_cost_center.invoice_accounting_item_id
    where invoice_accounting_item.invoice_document_id = result.document_id
  )
  and not exists (
    select from public.invoice_accounting_item_cost_unit
    join public.invoice_accounting_item on invoice_accounting_item.id = invoice_accounting_item_cost_unit.invoice_accounting_item_id
    where invoice_accounting_item.invoice_document_id = result.document_id
  )
  then
    delete from public.invoice_accounting_item where invoice_accounting_item.invoice_document_id = result.document_id;

    perform public.generate_invoice_accounting_items(
      result.document_id,
      result.extracted_vat_groups
    );
  end if;

  -- delete and rematch money transactions on each invoice update
  -- if they are matched automatically and not older than 14 days
  if (
    select not exists(
      select from public.document_money_transaction
      where document_money_transaction.document_id = result.document_id
      and (
        -- created manually
        document_money_transaction.created_by is not null
        or document_money_transaction.confirmed_by is not null -- deprecated
        -- or created automatically but older than 14 days
        or (
          document_money_transaction.created_by is null
          and document_money_transaction.confirmed_by is null -- deprecated
          and document_money_transaction.created_at < (current_date - interval '14 days')
        )
      )
    )
  ) then
    perform from
      public.document_money_transaction,
      public.delete_document_money_transaction(
        result.document_id,
        document_money_transaction.money_transaction_id
      )
    where document_money_transaction.document_id = result.document_id;

    perform matching.match_invoices(array[result.document_id]);
  end if;

  -- update matched cash-transactions with new amount (everything else stays)
  update public.cash_transaction
  set
    "type"=(case when coalesce(public.invoice_signed_total(result), 0) < 0 then 'OUTGOING' else 'INCOMING' end)::public.cash_transaction_type,
    amount=abs(public.invoice_signed_total(result)),
    updated_at=now()
  from public.document_cash_transaction
  where document_cash_transaction.cash_transaction_id = cash_transaction.id
  and document_cash_transaction.document_id = result.document_id;

  RETURN result;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.update_invoice IS 'Updates the specified `Invoice` and sets the changed values confirmations to the `currentUser`.';

----

create function public.update_invoices(
  invoice_document_ids uuid[],
  -- fields
  invoice_date                       date = null,
  change_invoice_date                boolean = false,
  due_date                           date = null,
  change_due_date                    boolean = false,
  paid_date                          date = null,
  change_paid_date                   boolean = false,
  payment_status                     public.invoice_payment_status = null,
  change_payment_status              boolean = false,
  currency                           public.currency_code = null,
  change_currency                    boolean = false,
  partner_company_id                 uuid = null,
  change_partner_company_id          boolean = false,
  partner_company_location_id        uuid = null,
  change_partner_company_location_id boolean = false,
  iban                               public.bank_iban = null,
  change_iban                        boolean = false,
  bic                                public.bank_bic = null,
  change_bic                         boolean = false,
  payment_reference                  text = null,
  change_payment_reference           boolean = false,
  credit_memo                        boolean = null,
  change_credit_memo                 boolean = false,
  discount_percent                   float8 = null,
  change_discount_percent            boolean = false,
  discount_amount                    float8 = null,
  change_discount_amount             boolean = false,
  discount_until                     date = null,
  change_discount_until              boolean = false,
  delivered_from                     date = null,
  change_delivered_from              boolean = false,
  delivered_until                    date = null,
  change_delivered_until             boolean = false,
  conversion_rate                    float8 = null,
  change_conversion_rate             boolean = false,
  partially_paid                     boolean = null,
  change_partially_paid              boolean = false
) returns setof public.invoice as $$
  select public.update_invoice(
    invoice.document_id,
    invoice.invoice_number,
    invoice.order_number,
    invoice.internal_number,
    case change_invoice_date when true then update_invoices.invoice_date else invoice.invoice_date end,
    invoice.order_date,
    case change_due_date when true then update_invoices.due_date else invoice.due_date end,
    case change_paid_date when true then update_invoices.paid_date else invoice.paid_date end,
    case change_payment_status when true then update_invoices.payment_status else invoice.payment_status end,
    invoice.net,
    invoice.total,
    case change_currency when true then update_invoices.currency else invoice.currency end,
    case change_partner_company_id when true then update_invoices.partner_company_id else invoice.partner_company_id end,
    case change_partner_company_location_id when true then update_invoices.partner_company_location_id else invoice.partner_company_location_id end,
    case change_iban when true then update_invoices.iban else invoice.iban end,
    case change_bic when true then update_invoices.bic else invoice.bic end,
    case change_payment_reference when true then update_invoices.payment_reference else invoice.payment_reference end,
    case change_credit_memo when true then update_invoices.credit_memo else invoice.credit_memo end,
    invoice.credit_memo_for_invoice_document_id,
    case change_discount_percent when true then update_invoices.discount_percent else invoice.discount_percent end,
    case change_discount_amount when true then update_invoices.discount_amount else invoice.discount_amount end,
    case change_discount_until when true then update_invoices.discount_until else invoice.discount_until end,
    case change_delivered_from when true then update_invoices.delivered_from else invoice.delivered_from end,
    case change_delivered_until when true then update_invoices.delivered_until else invoice.delivered_until end,
    case change_conversion_rate when true then update_invoices.conversion_rate else invoice.conversion_rate end,
    case change_partially_paid when true then update_invoices.partially_paid else invoice.partially_paid end,
    null, -- recurring
    null, -- recurring_interval
    null, -- recurring_max_recurrences
    null, -- recurring_ends_at
    null, -- ger_clause_35a_net,
    null, -- ger_clause_35a_total,
    null  -- ger_clause_35a_kind,
  )
  from public.invoice
  where invoice.document_id = any(invoice_document_ids)
$$ language sql volatile;

comment on function public.update_invoices is 'Updates the `Invoice`s and sets the changed values confirmations to the `currentUser`. ';

----

CREATE FUNCTION public.update_invoice_payment(
  invoice_document_id uuid,
  payment_status      public.invoice_payment_status = NULL,
  paid_date           date = NULL
) RETURNS public.invoice AS
$$
  UPDATE public.invoice
    SET
      -- paid_date
      (paid_date, paid_date_confirmed_by, paid_date_confirmed_at) = (
        SELECT val::date, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice_payment.paid_date::text,
          paid_date::text,
          paid_date_confirmed_by,
          paid_date_confirmed_at
        )
      ),
      -- payment_status
      (payment_status, payment_status_confirmed_by, payment_status_confirmed_at) = (
        SELECT val::public.invoice_payment_status, conf_by, conf_at FROM private.calc_invoice_value_fields(
          update_invoice_payment.payment_status::text,
          payment_status::text,
          payment_status_confirmed_by,
          payment_status_confirmed_at
        )
      ),
      updated_at=now()
  WHERE (document_id = update_invoice_payment.invoice_document_id)
  RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

create function public.update_invoice_pay_from_bank_account(
  invoice_document_id      uuid,
  pay_from_bank_account_id uuid = null
) returns public.invoice as $$
  update public.invoice
  set
    (pay_from_bank_account_id, pay_from_bank_account_id_confirmed_by, pay_from_bank_account_id_confirmed_at) = (
      select val::uuid, conf_by, conf_at from private.calc_invoice_value_fields(
        update_invoice_pay_from_bank_account.pay_from_bank_account_id::text,
        pay_from_bank_account_id::text,
        pay_from_bank_account_id_confirmed_by,
        pay_from_bank_account_id_confirmed_at
      )
    ),
    updated_at=now()
  where document_id = update_invoice_pay_from_bank_account.invoice_document_id
  returning *
$$ language sql volatile;
