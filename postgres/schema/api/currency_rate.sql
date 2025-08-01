CREATE VIEW api.currency_rate WITH (security_barrier) AS 
    SELECT * FROM public.currency_rate;

GRANT SELECT ON TABLE api.currency_rate TO domonda_api;

COMMENT ON COLUMN api.currency_rate."date" IS '@notNull';
COMMENT ON COLUMN api.currency_rate.currency IS '@notNull';
COMMENT ON COLUMN api.currency_rate.rate IS '@notNull';
COMMENT ON VIEW api.currency_rate IS $$
@primaryKey "date",currency
A `CurrencyRate` is a rate of currency conversion on a given date.$$;
