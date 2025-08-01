---- invoice ----

insert into public.document_field (name, "type", id)
values (
  'partner_company_id',
  'PARTNER_COMPANY',
  '02dc8742-60ea-459f-9df1-d132cc1905eb'
);

insert into public.document_field (name, "type", id)
values (
  'partner_company_location_id',
  'COMPANY_LOCATION',
  '0b6d135d-7ce1-43e0-a135-37929a7697b6'
);

insert into public.document_field (name, "type", id)
values (
  'invoice_number',
  'TEXT',
  '9633c569-7119-40bc-9113-0a6604daecd3'
);

insert into public.document_field (name, "type", id)
values (
  'order_number',
  'TEXT',
  'f1adeead-efc1-4d34-b06e-84d47ad6a461'
);

insert into public.document_field (name, "type", id)
values (
  'internal_number',
  'TEXT',
  'ec32c90f-ea47-485b-b59a-db4950109296'
);

insert into public.document_field (name, "type", id)
values (
  'invoice_date',
  'DATE',
  'f657537d-be72-42af-b3fc-08f7a676e7da'
);

insert into public.document_field (name, "type", id)
values (
  'order_date',
  'DATE',
  '6822eedf-1092-4bca-baa5-e225b720b4f5'
);

insert into public.document_field (name, "type", id)
values (
  'net',
  'NUMBER',
  'f82cdb8a-1d93-4c80-a5a3-354dec8bd7e7'
);

insert into public.document_field (name, "type", id)
values (
  'total',
  'NUMBER',
  '224dc2a8-2550-4c06-89b7-7610c71afeef'
);

insert into public.document_field (name, "type", id)
values (
  'vat_percent',
  'NUMBER',
  '1917fa18-dffd-4739-9755-491c6eb9b8c1'
);

insert into public.document_field (name, "type", id)
values (
  'discount_percent',
  'NUMBER',
  'dab9fc7f-003a-4be4-9d7b-c3d7d7ea4c75'
);

insert into public.document_field (name, "type", id)
values (
  'discount_amount',
  'NUMBER',
  '0554c279-3ac7-4cdf-9352-bf47453fba7e'
);

insert into public.document_field (name, "type", id)
values (
  'discount_until',
  'DATE',
  '096ce5a9-e25a-4a5e-b8b7-501841b68e8b'
);

insert into public.document_field (name, "type", id)
values (
  'currency',
  'CURRENCY',
  '768984ed-cfb7-4526-95b3-a1bafe65cac4'
);

insert into public.document_field (name, "type", id)
values (
  'goods_services',
  'TEXT',
  '4cfc4804-240a-4d75-82e7-e1b08ddb2b59'
);

insert into public.document_field (name, "type", id)
values (
  'delivered_from',
  'DATE',
  '772a840d-ac58-4225-bd97-1590c4b0e219'
);

insert into public.document_field (name, "type", id)
values (
  'delivered_until',
  'DATE',
  '6da83820-67f2-4c1f-8924-bc50cd64c1f4'
);

insert into public.document_field (name, "type", id)
values (
  'iban',
  'IBAN',
  '63857169-2a58-4585-96a9-343aa99b2577'
);

insert into public.document_field (name, "type", id)
values (
  'bic',
  'BIC',
  '09a8bcad-9890-44b6-ae6d-beb299ded869'
);

insert into public.document_field (name, "type", id)
values (
  'due_date',
  'DATE',
  '8ae1d065-61f6-4092-9b99-8b40d55a0570'
);

insert into public.document_field (name, "type", id)
values (
  'payment_status',
  'INVOICE_PAYMENT_STATUS',
  'cb5b3534-7f83-4087-ba1e-dd05b0e556e7'
);

insert into public.document_field (name, "type", id)
values (
  'payment_reference',
  'TEXT',
  'b415b6b5-9fc6-48d7-84ff-8f64646fede5'
);

insert into public.document_field (name, "type", id)
values (
  'paid_date',
  'DATE',
  '6fbe01d1-6ee7-47e1-b58b-4188597d2f7b'
);

insert into public.document_field (name, "type", id)
values (
  'credit_memo',
  'BOOLEAN',
  'a0279fbc-28f0-4fae-b717-144ce9f2136c'
);

insert into public.document_field (name, "type", id)
values (
  'credit_memo_for_invoice_document_id',
  'INVOICE',
  '5db1d952-7d7f-4bd1-bd28-e056814e14d9'
);

insert into public.document_field (name, "type", id)
values (
  'partially_paid',
  'BOOLEAN',
  'bbbb3e2c-14ee-436c-9ade-f278d9ecd2b6'
);

---- other_document ----

insert into public.document_field (name, "type", id)
values (
  'other_document_type',
  'OTHER_DOCUMENT_TYPE',
  '9ce46ec4-8d7e-4593-9c72-9f1041e2e5f9'
);

-- partner_company_id is reused

insert into public.document_field (name, "type", id)
values (
  'document_date',
  'DATE',
  '4de2e5c4-b13c-4897-94ed-661e42f9a1d4'
);

insert into public.document_field (name, "type", id)
values (
  'document_number',
  'TEXT',
  '8e52a496-1dc1-4604-9ed2-ef5ca0aedd7f'
);

insert into public.document_field (name, "type", id)
values (
  'document_details',
  'TEXT',
  '3be7bdb3-b7bb-482f-a7e4-50fe81afdc2c'
);

insert into public.document_field (name, "type", id)
values (
  'resubmission_date',
  'DATE',
  '95f56b03-0061-48ad-bc90-039394deb9bc'
);

insert into public.document_field (name, "type", id)
values (
  'expiry_date',
  'DATE',
  '16603cbc-4371-4735-86e7-4a649cadb2bd'
);

insert into public.document_field (name, "type", id)
values (
  'contract_type',
  'OTHER_DOCUMENT_CONTRACT_TYPE',
  'aaa53680-1c6c-40cb-9ec4-17e670f8028f'
);

-- TODO: add document field type USER
insert into public.document_field (name, "type", id)
values (
  'contact_user_id',
  'TEXT',
  '8e1f6e62-a2cd-4e10-8a64-19047f3939b0'
);
