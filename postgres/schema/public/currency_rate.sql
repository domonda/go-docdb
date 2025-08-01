CREATE TABLE public.currency_rate (
    "date"     date NOT NULL,
    currency   currency_code NOT NULL,
    PRIMARY KEY(date, currency),

    rate       float8 NOT NULL CHECK(rate > 0),
    created_at created_time NOT NULL
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.currency_rate TO domonda_user;