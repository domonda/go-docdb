CREATE VIEW api.document_money_transaction WITH (security_barrier) AS
    SELECT
        dmt.document_id,
        dmt.money_transaction_id,
        dmt.created_by,
        dmt.check_id,
        dmt.check_id_confirmed_by,
        dmt.check_id_confirmed_at,
        dmt.updated_at,
        dmt.created_at
    FROM public.document_money_transaction AS dmt
        INNER JOIN api.document AS d ON (d.id = dmt.document_id);

GRANT SELECT ON TABLE api.document_money_transaction TO domonda_api;

COMMENT ON COLUMN api.document_money_transaction.document_id IS '@notNull';
COMMENT ON COLUMN api.document_money_transaction.money_transaction_id IS '@notNull';
COMMENT ON VIEW api.document_money_transaction IS $$
@foreignKey (document_id) references api.document (id)
@foreignKey (money_transaction_id) references api.money_transaction (id)
@foreignKey (created_by) references api.user (id)
@foreignKey (check_id_confirmed_by) references api.user (id)
A `DocumentMoneyTransaction` represents a match between a `Document` and a `MoneyTransaction`.$$;
