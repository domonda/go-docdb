create type public.bank_payment_status as enum (
  'CREATED',
  'FINISHED',
  'FAILED'
);

comment on type public.bank_payment_status is 'The status of the bank_payment.';

----

create table public.bank_payment (
  id                uuid primary key,
  bank_account_iban bank_iban not null references public.bank_account(iban) on delete cascade,

  status bank_payment_status not null,

  recipient_name    text not null,
  recipient_iban    bank_iban not null,
  recipient_bic     bank_bic,

  currency         currency_code not null,
  amount           float8 not null,
  discount_percent float8,
  discount_amount  float8,
  constraint discount_percent_or_amount_not_both_check check(
    (discount_percent is null and discount_amount is null) -- neither
    or (discount_percent is not null and discount_amount is null) -- only percent
    or (discount_percent is null and discount_amount is not null) -- only amount
  ),
  fee              float8 not null default 0,
  total            float8 not null,

  purpose   text, -- TODO: make non nullable

  document_id uuid references public.document(id) on delete set null,

  updated_at   updated_time not null,
  created_at   created_time not null
);

grant select on table public.bank_payment to domonda_user;
grant select on table public.bank_payment to domonda_wg_user;

create index bank_payment_document_id_idx on public.bank_payment (document_id);
create index bank_payment_paid_document_id_status_idx on public.bank_payment (document_id, status);
