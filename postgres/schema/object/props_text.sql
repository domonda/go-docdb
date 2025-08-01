create view object.props_text as (
  -- text_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    text_prop.id,
    text_prop.instance_id,
    text_prop.class_prop_id,
    text_prop.array_index,
    text_prop.updated_by,
    text_prop.updated_at,
    text_prop.created_by,
    text_prop.created_at,
    text_prop.value
  from object.text_prop
    join object.class_prop on class_prop.id = text_prop.class_prop_id
    join object.instance on instance.id = text_prop.instance_id
) union all (
  -- text_option_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    text_option_prop.id,
    text_option_prop.instance_id,
    text_option_prop.class_prop_id,
    text_option_prop.array_index,
    text_option_prop.updated_by,
    text_option_prop.updated_at,
    text_option_prop.created_by,
    text_option_prop.created_at,
    class_prop.options[text_option_prop.option_index+1] as value
  from object.text_option_prop
    join object.class_prop on class_prop.id = text_option_prop.class_prop_id
    join object.instance on instance.id = text_option_prop.instance_id
) union all (
  -- account_no_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    account_no_prop.id,
    account_no_prop.instance_id,
    account_no_prop.class_prop_id,
    account_no_prop.array_index,
    account_no_prop.updated_by,
    account_no_prop.updated_at,
    account_no_prop.created_by,
    account_no_prop.created_at,
    account_no_prop.value::text
  from object.account_no_prop
    join object.class_prop on class_prop.id = account_no_prop.class_prop_id
    join object.instance on instance.id = account_no_prop.instance_id
) union all (
  -- number_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    number_prop.id,
    number_prop.instance_id,
    number_prop.class_prop_id,
    number_prop.array_index,
    number_prop.updated_by,
    number_prop.updated_at,
    number_prop.created_by,
    number_prop.created_at,
    number_prop.value::text
  from object.number_prop
    join object.class_prop on class_prop.id = number_prop.class_prop_id
    join object.instance on instance.id = number_prop.instance_id
) union all (
  -- integer_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    integer_prop.id,
    integer_prop.instance_id,
    integer_prop.class_prop_id,
    integer_prop.array_index,
    integer_prop.updated_by,
    integer_prop.updated_at,
    integer_prop.created_by,
    integer_prop.created_at,
    integer_prop.value::text
  from object.integer_prop
    join object.class_prop on class_prop.id = integer_prop.class_prop_id
    join object.instance on instance.id = integer_prop.instance_id
) union all (
  -- boolean_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    boolean_prop.id,
    boolean_prop.instance_id,
    boolean_prop.class_prop_id,
    boolean_prop.array_index,
    boolean_prop.updated_by,
    boolean_prop.updated_at,
    boolean_prop.created_by,
    boolean_prop.created_at,
    boolean_prop.value::text
  from object.boolean_prop
    join object.class_prop on class_prop.id = boolean_prop.class_prop_id
    join object.instance on instance.id = boolean_prop.instance_id
) union all (
  -- date_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    date_prop.id,
    date_prop.instance_id,
    date_prop.class_prop_id,
    date_prop.array_index,
    date_prop.updated_by,
    date_prop.updated_at,
    date_prop.created_by,
    date_prop.created_at,
    date_prop.value::text
  from object.date_prop
    join object.class_prop on class_prop.id = date_prop.class_prop_id
    join object.instance on instance.id = date_prop.instance_id
) union all (
  -- date_time_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    date_time_prop.id,
    date_time_prop.instance_id,
    date_time_prop.class_prop_id,
    date_time_prop.array_index,
    date_time_prop.updated_by,
    date_time_prop.updated_at,
    date_time_prop.created_by,
    date_time_prop.created_at,
    date_time_prop.value::text
  from object.date_time_prop
    join object.class_prop on class_prop.id = date_time_prop.class_prop_id
    join object.instance on instance.id = date_time_prop.instance_id
) union all (
  -- iban_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    iban_prop.id,
    iban_prop.instance_id,
    iban_prop.class_prop_id,
    iban_prop.array_index,
    iban_prop.updated_by,
    iban_prop.updated_at,
    iban_prop.created_by,
    iban_prop.created_at,
    iban_prop.value::text
  from object.iban_prop
    join object.class_prop on class_prop.id = iban_prop.class_prop_id
    join object.instance on instance.id = iban_prop.instance_id
) union all (
  -- bic_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    bic_prop.id,
    bic_prop.instance_id,
    bic_prop.class_prop_id,
    bic_prop.array_index,
    bic_prop.updated_by,
    bic_prop.updated_at,
    bic_prop.created_by,
    bic_prop.created_at,
    bic_prop.value::text
  from object.bic_prop
    join object.class_prop on class_prop.id = bic_prop.class_prop_id
    join object.instance on instance.id = bic_prop.instance_id
) union all (
  -- vat_id_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    vat_id_prop.id,
    vat_id_prop.instance_id,
    vat_id_prop.class_prop_id,
    vat_id_prop.array_index,
    vat_id_prop.updated_by,
    vat_id_prop.updated_at,
    vat_id_prop.created_by,
    vat_id_prop.created_at,
    vat_id_prop.value::text
  from object.vat_id_prop
    join object.class_prop on class_prop.id = vat_id_prop.class_prop_id
    join object.instance on instance.id = vat_id_prop.instance_id
) union all (
  -- country_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    country_prop.id,
    country_prop.instance_id,
    country_prop.class_prop_id,
    country_prop.array_index,
    country_prop.updated_by,
    country_prop.updated_at,
    country_prop.created_by,
    country_prop.created_at,
    country_prop.value::text
  from object.country_prop
    join object.class_prop on class_prop.id = country_prop.class_prop_id
    join object.instance on instance.id = country_prop.instance_id
) union all (
  -- currency_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    currency_prop.id,
    currency_prop.instance_id,
    currency_prop.class_prop_id,
    currency_prop.array_index,
    currency_prop.updated_by,
    currency_prop.updated_at,
    currency_prop.created_by,
    currency_prop.created_at,
    currency_prop.value::text
  from object.currency_prop
    join object.class_prop on class_prop.id = currency_prop.class_prop_id
    join object.instance on instance.id = currency_prop.instance_id
) union all (
  -- currency_amount_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    currency_amount_prop.id,
    currency_amount_prop.instance_id,
    currency_amount_prop.class_prop_id,
    currency_amount_prop.array_index,
    currency_amount_prop.updated_by,
    currency_amount_prop.updated_at,
    currency_amount_prop.created_by,
    currency_amount_prop.created_at,
    public.currency_amount_text(currency_amount_prop.value) as value
  from object.currency_amount_prop
    join object.class_prop on class_prop.id = currency_amount_prop.class_prop_id
    join object.instance on instance.id = currency_amount_prop.instance_id
) union all (
  -- email_address_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    email_address_prop.id,
    email_address_prop.instance_id,
    email_address_prop.class_prop_id,
    email_address_prop.array_index,
    email_address_prop.updated_by,
    email_address_prop.updated_at,
    email_address_prop.created_by,
    email_address_prop.created_at,
    email_address_prop.value::text
  from object.email_address_prop
    join object.class_prop on class_prop.id = email_address_prop.class_prop_id
    join object.instance on instance.id = email_address_prop.instance_id
) union all (
  -- user_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    user_prop.id,
    user_prop.instance_id,
    user_prop.class_prop_id,
    user_prop.array_index,
    user_prop.updated_by,
    user_prop.updated_at,
    user_prop.created_by,
    user_prop.created_at,
    user_prop.value::text
  from object.user_prop
    join object.class_prop on class_prop.id = user_prop.class_prop_id
    join object.instance on instance.id = user_prop.instance_id
) union all (
  -- bank_account_prop
  select
    class_prop.class_name,
    class_prop.name,
    class_prop.type,
    class_prop.required,
    class_prop.options,
    class_prop.description,
    class_prop.pos,
    instance.client_company_id,
    instance.disabled_by as instance_disabled_by,
    instance.disabled_at as instance_disabled_at,
    bank_account_prop.id,
    bank_account_prop.instance_id,
    bank_account_prop.class_prop_id,
    bank_account_prop.array_index,
    bank_account_prop.updated_by,
    bank_account_prop.updated_at,
    bank_account_prop.created_by,
    bank_account_prop.created_at,
    object.bank_account_prop_value(bank_account_prop)::text as value
  from object.bank_account_prop
    join object.class_prop on class_prop.id = bank_account_prop.class_prop_id
    join object.instance on instance.id = bank_account_prop.instance_id
);

comment on column object.props_text.class_name is '@notNull';
comment on column object.props_text.name is '@notNull';
comment on column object.props_text.type is '@notNull';
comment on column object.props_text.required is '@notNull';
comment on column object.props_text.pos is '@notNull';
comment on column object.props_text.id is '@notNull';
comment on column object.props_text.client_company_id is '@notNull';
comment on column object.props_text.instance_id is '@notNull';
comment on column object.props_text.class_prop_id is '@notNull';
comment on column object.props_text.array_index is '@notNull';
comment on column object.props_text.updated_by is '@notNull';
comment on column object.props_text.updated_at is '@notNull';
comment on column object.props_text.created_by is '@notNull';
comment on column object.props_text.created_at is '@notNull';
comment on column object.props_text.value is '@notNull';
comment on view object.props_text is $$
@primaryKey id
@foreignKey (class_name) references object.class(name)
@foreignKey (client_company_id) references public.client_company(id)
@foreignKey (instance_id) references object.instance(id)
@foreignKey (class_prop_id) references object.class_prop(id)
All object props converted to text$$;
