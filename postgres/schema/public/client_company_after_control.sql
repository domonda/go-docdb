create type public.client_company_license_usage_result as (
  start_date date,
  end_date date,
  documents_count int,
  users_count int,
  banks_count int,
  predicted_documents_count int
);

comment on column public.client_company_license_usage_result.start_date is '@notNull';
comment on column public.client_company_license_usage_result.end_date is '@notNull';
comment on column public.client_company_license_usage_result.documents_count is '@notNull';
comment on column public.client_company_license_usage_result.users_count is '@notNull';
comment on column public.client_company_license_usage_result.banks_count is '@notNull';
comment on column public.client_company_license_usage_result.predicted_documents_count is '@notNull';

create function public.client_company_license_usage(
  client_company public.client_company,
  from_date date,
  until_date date
) returns public.client_company_license_usage_result as $$
  with billed_companies as (
    select company_id from public.client_company
    where client_company.billed_client_company_id = client_company_license_usage.client_company.company_id
  ), documents as (
    select coalesce(count(1), 0) as count from public.document
      left join public.invoice on invoice.document_id = document.id
    where (
      document.client_company_id = client_company_license_usage.client_company.company_id
      or document.client_company_id in (select company_id from billed_companies)
    )
    and document.import_date::date >= client_company_license_usage.from_date
    and document.import_date::date <= client_company_license_usage.until_date
    and (
      not document.superseded
      -- if the document is deleted, check if the invoice is processed by external service
      or invoice.extracted_partner_name is not null
      or invoice.partner_company_id_confirmed_by is not null
      or invoice.invoice_number_confirmed_by is not null
      or invoice.invoice_date_confirmed_by is not null
      or invoice.total_confirmed_by is not null
    )
  ), users as (
    select coalesce(count(1), 0) as count from public."user"
    where (
      "user".client_company_id = client_company_license_usage.client_company.company_id
      or "user".client_company_id in (select company_id from billed_companies)
    )
    and "user".created_at::date <= client_company_license_usage.until_date
    and exists (
      select from control.client_company_user where client_company_user.user_id = "user".id
    )
    and "user".type in ('STANDARD', 'SUPER_ADMIN')
    and "user".enabled
  ), banks as (
    select coalesce(count(1), 0) as count from public.money_account
    where (
      money_account.client_company_id = client_company_license_usage.client_company.company_id
      or money_account.client_company_id in (select company_id from billed_companies)
    )
    and money_account.created_at::date <= client_company_license_usage.until_date
    and money_account.xs2a_account_id is not null
    and money_account.active
  )
  select
    client_company_license_usage.from_date as start_date,
    client_company_license_usage.until_date as end_date,
    documents.count as documents_count,
    users.count as users_count,
    banks.count as banks_count,
    (select coalesce(round(
      documents.count::decimal
      / nullif(current_date - client_company_license_usage.from_date, 0)
      * (client_company_license_usage.until_date - client_company_license_usage.from_date)
    ), 0)) as predicted_documents_count
  from documents, users, banks
$$ language sql stable strict;
comment on function public.client_company_license_usage is '@notNull';
