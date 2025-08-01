CREATE VIEW api.credit_card_account WITH (security_barrier) AS 
    SELECT
        cca.id,
        cca.client_company_id,
        cca.bank_account_id,
        cca."number",
        cca."type",
        cca.name,
        cca.currency ,
        cca.available,
        cca."limit",
        cca.balance,
        cca.updated_at::updated_time,
        cca.created_at::created_time
    FROM public.credit_card_account AS cca
        INNER JOIN api.client_company AS cc ON (cc.company_id = cca.client_company_id);

GRANT SELECT ON TABLE api.credit_card_account TO domonda_api;

COMMENT ON COLUMN api.credit_card_account.client_company_id IS '@notNull';
COMMENT ON COLUMN api.credit_card_account."number" IS '@notNull';
COMMENT ON COLUMN api.credit_card_account."type" IS '@notNull';
COMMENT ON COLUMN api.credit_card_account.name IS '@notNull';
COMMENT ON COLUMN api.credit_card_account.currency IS '@notNull';
COMMENT ON VIEW api.credit_card_account IS $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
@foreignKey (bank_account_id) references api.bank_account (id)$$;
