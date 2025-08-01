create type public.audit_trail_pos as enum (
  'PREPEND',
  'APPEND'
);

comment on type public.audit_trail_pos is 'The audit trail position used for document exports with audit log';

----

create table public.export (
  id uuid primary key default uuid_generate_v4(),

  client_company_id uuid not null references public.client_company(company_id) on delete cascade,
  created_by        uuid not null default public.unknown_user_id() references public.user(id) on delete set default,

  spreadsheets                          boolean not null default false,
  factor_excel                          boolean not null default false,
  pdfs                                  boolean not null default false,
  pdfs_with_info_pages_tags             boolean not null default false,
  pdfs_with_info_pages_cost_centers     boolean not null default false,
  pdfs_with_info_pages_cost_units       boolean not null default false,
  pdfs_with_info_pages_workflow_history boolean not null default false,
  pdfs_with_info_pages_comments         boolean not null default false,
  xml_embedded                          boolean not null default false,

  constraint pdfs_required_for_info_pages_tags check(case pdfs_with_info_pages_tags when true then pdfs else true end),
  constraint pdfs_required_for_info_pages_cost_centers check(case pdfs_with_info_pages_cost_centers when true then pdfs else true end),
  constraint pdfs_required_for_info_pages_cost_units check(case pdfs_with_info_pages_cost_units when true then pdfs else true end),
  constraint pdfs_required_for_info_pages_workflow_history check(case pdfs_with_info_pages_workflow_history when true then pdfs else true end),
  constraint pdfs_required_for_info_pages_comments check(case pdfs_with_info_pages_comments when true then pdfs else true end),

  audit_trail_pos public.audit_trail_pos,

  accounting_export public.accounting_system,
  constraint require_one_flag check(spreadsheets or factor_excel or pdfs or (accounting_export is not null)),
  accounting_period date, -- necessary for ready for booking or booking exports

  ready_for_booking_export boolean not null default false, -- done by clients to indicate to accountants booking is ready to start
  booking_export           boolean not null default false, -- flags invoices as booked
  allow_incomplete         boolean not null default false, -- create export even if some data is missing
  constraint booking_or_ready_for_booking check(not (ready_for_booking_export and booking_export)),
  constraint accounting_period_exists_booking check(
    not booking_export
    or (booking_export and (accounting_period is not null))
  ),
  constraint accounting_period_exists_ready_for_booking check(
    not ready_for_booking_export
    or (ready_for_booking_export and (accounting_period is not null))
  ),

  -- build_percent float8 check(build_percent >= 0 and build_percent <= 100),
  -- build_error   text   check(length(trim(build_error)) > 0),

  created_at created_time not null
);

-- no insert grant because the entries are created by the backend
grant select on table public.export to domonda_user;

create index export_client_company_id_idx on public.export (client_company_id);
create index export_created_by_idx on public.export (created_by);
create index export_accounting_period_month_idx on public.export (date_trunc('month', accounting_period::timestamp));
create index export_booking_export_idx on public.export (booking_export);
create index export_ready_for_booking_export_idx on public.export (ready_for_booking_export);
create index export_created_at_idx on public.export (created_at);

----

create table public.export_document (
  export_id uuid not null references public.export(id) on delete cascade,

  -- In case of derived documents this is a version of the base document
  -- because derived documents don't have own versions
  document_version_id uuid not null references docdb.document_version(id) on delete restrict, -- no purging of documents when exported

  -- Even though the document ID can be found through the version ID, the versions table
  -- has milions of entries and lookups are not that fast (event with indexes)
  document_id uuid not null references public.document on delete cascade,

  removed_at timestamptz,
  removed_by uuid default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- Unknown user
      references public.user(id) on delete set default,
  constraint removed_at_and_by check((removed_at is null) = (removed_by is null))
);

-- no insert grant because the entries are created by the backend
grant select on table public.export_document to domonda_user;

create index export_document_export_id_idx on public.export_document (export_id);
create index export_document_document_version_id_idx on public.export_document (document_version_id);
create index export_document_document_id_idx on public.export_document (document_id);
-- TODO make export_document_export_id_document_version_id_idx a unique index,
-- but we inserted non unique document version ids into the db!!!
-- Example: select * from public.document_version where id = '98f2b3c4-d814-478d-8d6b-7a0f087d4934';
-- The document version is not that critical, so we don't have to fix that immediately.
create index export_document_export_id_document_version_id_idx on public.export_document (export_id, document_version_id);
create unique index export_document_export_id_document_id_idx on public.export_document (export_id, document_id);
create index export_document_removed_at_idx on public.export_document (removed_at);
create index export_document_removed_by_idx on public.export_document (removed_by);

----

create table public.export_money_transaction (
  export_id            uuid not null references public.export(id) on delete cascade,
  -- TODO-db-210902 no deleting money transactions when exported?
  -- TODO-db-210902 money_transaction is a view and cannot references public.money_transaction(id)
  money_transaction_id uuid not null,
  primary key(export_id, money_transaction_id)

  -- TODO-db-210902 When exporting transactions, the relevant matches will be in the files.
  --                Do we want to store document matches here in the table too?
);

-- no insert grant because the entries are created by the backend
grant select on table public.export_money_transaction to domonda_user;

create index export_money_transaction_export_id_idx on public.export_money_transaction (export_id);
create index export_money_transaction_money_transaction_id_idx on public.export_money_transaction (money_transaction_id);

----

create function public.client_company_accounting_period_ready_for_booking_export(
    client_company public.client_company,
    period date
) returns public.export as $$
    select * from public.export
    where export.client_company_id = client_company.company_id
      and date_trunc('month', export.accounting_period) = date_trunc('month', period)
      and export.ready_for_booking_export
    order by created_at desc
    limit 1
$$ language sql stable strict;

create function public.client_company_accounting_period_is_ready_for_booking(
    client_company public.client_company,
    period date
) returns boolean as $$
    select exists(
        select from public.export
        where export.client_company_id = client_company.company_id
          and date_trunc('month', export.accounting_period) = date_trunc('month', period)
          and export.ready_for_booking_export
    )
$$ language sql stable strict;

comment on function public.client_company_accounting_period_is_ready_for_booking is '@notNull';

----

create function public.client_company_accounting_period_booking_export(
    client_company public.client_company,
    period date
) returns public.export as $$
    select * from public.export
    where export.client_company_id = client_company.company_id
      and date_trunc('month', export.accounting_period) = date_trunc('month', period)
      and export.booking_export
    order by created_at desc
    limit 1
$$ language sql stable strict;

create function public.client_company_accounting_period_is_booked(
    client_company public.client_company,
    period date
) returns boolean as $$
    select exists(
        select from public.export
        where export.client_company_id = client_company.company_id
          and date_trunc('month', export.accounting_period) = date_trunc('month', period)
          and export.booking_export
    )
$$ language sql stable strict;

comment on function public.client_company_accounting_period_is_booked is '@notNull';

----

create function public.remove_document_from_all_booking_exports(
    document_id uuid
) returns public.document as $$
declare
    document public.document;
begin
    if private.current_user_id() is null then
        raise exception 'Only authenticated users may remove documents from booking exports.';
    end if;

    select * into document
    from public.document as table_document
    where table_document.id = remove_document_from_all_booking_exports.document_id;

    if not private.current_user_super()
        and not exists(
            select from control.client_company_user
            where client_company_user.user_id = private.current_user_id()
              and client_company_user.client_company_id = document.client_company_id
              and client_company_user.role_name in ('ADMIN', 'ACCOUNTANT')
        )
    then
        raise exception 'You cannot remove this document from booking exports.';
    end if;

    update public.export_document
    set removed_at=now(),
        removed_by=private.current_user_id()
    from public.export
    where export_document.document_id = remove_document_from_all_booking_exports.document_id
      and export.id = export_document.export_id
      and export.booking_export
      and removed_at is null;

    return document;
end
$$ language plpgsql volatile strict
security definer; -- protected by implementation, see above
