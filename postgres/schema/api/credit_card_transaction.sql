CREATE VIEW api.credit_card_transaction WITH (security_barrier) AS 
    SELECT
        cct.id,
        cct.account_id,
        cct.partner_name,
        cct.partner_company_id,
        cct."type",
        cct.fee,
        cct.tax,
        cct.amount,
        cct.foreign_currency,
        cct.foreign_amount,
        cct.reference,
        cct.booking_date,
        cct.value_date,
        cct.import_document_id,
        cct.updated_at::updated_time,
        cct.created_at::created_time
    FROM public.credit_card_transaction AS cct
        INNER JOIN api.credit_card_account AS cca ON (cca.id = cct.account_id);

GRANT SELECT ON TABLE api.credit_card_transaction TO domonda_api;

COMMENT ON COLUMN api.credit_card_transaction.account_id IS '@notNull';
COMMENT ON COLUMN api.credit_card_transaction."type" IS '@notNull';
COMMENT ON COLUMN api.credit_card_transaction.amount IS '@notNull';
COMMENT ON COLUMN api.credit_card_transaction.booking_date IS '@notNull';
COMMENT ON VIEW api.credit_card_transaction IS $$
@primaryKey id
@foreignKey (account_id) references api.credit_card_account (id)
@foreignKey (partner_company_id) references api.partner_company (id)
@foreignKey (import_document_id) references api.document (id)$$;
