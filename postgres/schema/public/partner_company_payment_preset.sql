create table public.partner_company_payment_preset (
    id uuid primary key default uuid_generate_v4(),

    partner_company_id uuid not null references public.partner_company(id) on delete cascade,

    "primary" boolean not null default false,
    -- TODO add description column to identify multiple payment presets per partner company

    bank_account_id  uuid references public.bank_account(id) on delete set null, -- the preferred bank to pay with
    iban             public.bank_iban not null,
    bic              public.bank_bic,
    currency         public.currency_code,
    due_date_in_days int not null default 0 check (due_date_in_days >= 0),

    discount_percent          float8 check (discount_percent >= 0),
    discount_amount           float8 check (discount_percent >= 0),
    constraint discount_percent_or_amount_not_both_check check(
        (discount_percent is null and discount_amount is null) -- neither
        or (discount_percent is not null and discount_amount is null) -- only percent
        or (discount_percent is null and discount_amount is not null) -- only amount
    ),

    discount_due_date_in_days int check (discount_due_date_in_days >= 0),

    constraint discount_and_discount_due_date_in_days_set_check check(
        ((discount_percent is null) = (discount_due_date_in_days is null))
        or ((discount_amount is null) = (discount_due_date_in_days is null))
    ), -- both set or both null

    purpose_prefix text,

    updated_at updated_time not null,
    created_at created_time not null
);

grant all on table public.partner_company_payment_preset to domonda_user;
grant select on public.partner_company_payment_preset to domonda_wg_user;

create unique index partner_company_payment_preset_only_one_primary on public.partner_company_payment_preset (partner_company_id) where ("primary");
create unique index partner_company_payment_preset_unique_partner_iban on public.partner_company_payment_preset (partner_company_id, iban);

-- Erik: dropped, do we really need those?
-- create unique index partner_company_payment_preset_unique_partner_currency on public.partner_company_payment_preset (partner_company_id, currency);
-- create unique index partner_company_payment_preset_unique_partner_currency_null on public.partner_company_payment_preset (partner_company_id) where (currency is null);

create index partner_company_payment_preset_partner_company_id_idx on public.partner_company_payment_preset (partner_company_id);
create index partner_company_payment_preset_currency_idx on public.partner_company_payment_preset(currency);

comment on constraint discount_and_discount_due_date_in_days_set_check on public.partner_company_payment_preset is '@error Both the discount percent and discount due date have to be set or be empty';

----

create function public.create_partner_company_payment_preset(
    partner_company_id        uuid,
    "primary"                 boolean,
    iban                      public.bank_iban,
    due_date_in_days          int,
    discount_percent          float8 = null,
    discount_amount           float8 = null,
    discount_due_date_in_days int = null,
    bank_account_id           uuid = null,
    bic                       public.bank_bic = null,
    currency                  public.currency_code = null,
    purpose_prefix            text = null
) returns public.partner_company_payment_preset as $$
    insert into public.partner_company_payment_preset (
        partner_company_id,
        "primary",
        iban,
        due_date_in_days,
        discount_percent,
        discount_amount,
        discount_due_date_in_days,
        bank_account_id,
        bic,
        currency,
        purpose_prefix
    ) values (
        create_partner_company_payment_preset.partner_company_id,
        create_partner_company_payment_preset."primary",
        create_partner_company_payment_preset.iban,
        create_partner_company_payment_preset.due_date_in_days,
        create_partner_company_payment_preset.discount_percent,
        create_partner_company_payment_preset.discount_amount,
        create_partner_company_payment_preset.discount_due_date_in_days,
        create_partner_company_payment_preset.bank_account_id,
        create_partner_company_payment_preset.bic,
        create_partner_company_payment_preset.currency,
        create_partner_company_payment_preset.purpose_prefix
    )
    returning *
$$ language sql volatile;

----

create function public.update_partner_company_payment_preset(
    id                        uuid,
    "primary"                 boolean,
    iban                      public.bank_iban,
    due_date_in_days          int,
    discount_percent          float8 = null,
    discount_amount           float8 = null,
    discount_due_date_in_days int = null,
    bank_account_id           uuid = null,
    bic                       public.bank_bic = null,
    currency                  public.currency_code = null,
    purpose_prefix            text = null
) returns public.partner_company_payment_preset as $$
    update public.partner_company_payment_preset set
        "primary"=update_partner_company_payment_preset."primary",
        iban=update_partner_company_payment_preset.iban,
        due_date_in_days=update_partner_company_payment_preset.due_date_in_days,
        discount_percent=update_partner_company_payment_preset.discount_percent,
        discount_amount=update_partner_company_payment_preset.discount_amount,
        discount_due_date_in_days=update_partner_company_payment_preset.discount_due_date_in_days,
        bank_account_id=update_partner_company_payment_preset.bank_account_id,
        bic=update_partner_company_payment_preset.bic,
        currency=update_partner_company_payment_preset.currency,
        purpose_prefix=update_partner_company_payment_preset.purpose_prefix,
        updated_at=now()
    where id = update_partner_company_payment_preset.id
    returning *
$$ language sql volatile;

----

create function public.delete_partner_company_payment_preset(
    id uuid
) returns public.partner_company_payment_preset as $$
    delete from public.partner_company_payment_preset
    where id = delete_partner_company_payment_preset.id
    returning *
$$ language sql volatile;

----

create function public.primary_or_newest_payment_preset_for_partner_company(
    partner_company_id uuid
) returns public.partner_company_payment_preset as $$
    select * from public.partner_company_payment_preset
    where partner_company_payment_preset.partner_company_id = primary_or_newest_payment_preset_for_partner_company.partner_company_id
    order by
        "primary" desc, -- `true` on top
        created_at desc -- newest on top
    limit 1
$$ language sql stable strict;

----

create function public.primary_or_newest_currency_payment_preset_for_partner_company(
    partner_company_id uuid,
    currency           public.currency_code
) returns public.partner_company_payment_preset as $$
    select * from public.partner_company_payment_preset
    where partner_company_payment_preset.partner_company_id = primary_or_newest_currency_payment_preset_for_partner_company.partner_company_id
    and (
        partner_company_payment_preset.currency = primary_or_newest_currency_payment_preset_for_partner_company.currency
        or partner_company_payment_preset.currency is null
    )
    order by
        currency nulls last,
        "primary" desc, -- `true` on top
        created_at desc -- newest on top
    limit 1
$$ language sql stable strict;

----

create function public.preferred_payment_preset_bank_account_for_partner_company(
    partner_company_id uuid,
    currency           public.currency_code
) returns public.bank_account as $$
	select * from public.bank_account
    where bank_account.id = (
        public.primary_or_newest_currency_payment_preset_for_partner_company(
            preferred_payment_preset_bank_account_for_partner_company.partner_company_id,
            preferred_payment_preset_bank_account_for_partner_company.currency
        )
    ).bank_account_id
$$ language sql stable strict;

----

create function public.partner_company_primary_or_newest_payment_preset(
    partner_company public.partner_company
) returns public.partner_company_payment_preset as $$
    select * from public.primary_or_newest_payment_preset_for_partner_company(partner_company.id)
$$ language sql stable strict;
