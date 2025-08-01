create type public.source_file_status as enum (
  'IDLING',     -- just is there, nothing happening (waiting for a job maybe)
  'PROCESSING', -- is currently being processed
  'IMPORTABLE', -- content has been read out and is ready to be imported
  'PROCESSED',  -- is successfuly processed
  'DUPLICATE',  -- duplicate detected
  'ERROR'       -- error during processing
);

create function public.source_file_status(
  source_file public.source_file
) returns public.source_file_status as
$$
  select
    case
      when source_file.processing_error is not null then 'ERROR'::public.source_file_status
      when source_file.duplicate_document_id is not null then 'DUPLICATE'::public.source_file_status
      when source_file.resulting_document_id is not null then 'PROCESSED'::public.source_file_status
      when exists (select from public.source_file_money_transactions
        where source_file_id = source_file.id
        and import_destination_bank_account_id is null
        and import_destination_credit_card_account_id is null)
      then 'IMPORTABLE'::public.source_file_status
      when (source_file.processing_started_at is not null
        and source_file.processing_ended_at is null)
      or exists (select from public.source_file_money_transactions
        where source_file_id = source_file.id
        -- because the user set the destination account
        and (import_destination_bank_account_id is not null
          or import_destination_credit_card_account_id is not null))
      then 'PROCESSING'::public.source_file_status
      else 'IDLING'::public.source_file_status
    end
$$
language sql stable;

comment on function public.source_file_status is '@notNull';

----

create function public.source_file_done(
  source_file public.source_file
) returns boolean as
$$
  select
    case public.source_file_status(source_file)
      when 'PROCESSED' then true
      when 'DUPLICATE' then true
      when 'ERROR' then true
      else false
    end
$$
language sql immutable;

comment on function public.source_file_done is E'@notNull\nA `SourceFile` is considered done when no further automatic actions can performed. Its either successfuly processed or requires manual user input.';

----

create function public.unprocessed_source_files(
  client_company_id uuid,
  added_by          uuid = (private.current_user()).id
) returns setof public.source_file as
$$
  select *
  from public.source_file
  where client_company_id = unprocessed_source_files.client_company_id
  and added_by = unprocessed_source_files.added_by
  and public.source_file_status(source_file) <> 'PROCESSED'
  order by created_at desc
$$
language sql stable;

----

create function public.importable_source_files(
  client_company_id uuid,
  added_by          uuid = (private.current_user()).id
) returns setof public.source_file as
$$
  select *
  from public.source_file
  where client_company_id = importable_source_files.client_company_id
  and added_by = importable_source_files.added_by
  and public.source_file_status(source_file) = 'IMPORTABLE'
  order by created_at desc
$$
language sql stable;

----

create function public.client_company_source_file_parallel_processing_limit_reached(
  client_company public.client_company
) returns boolean as
$$
  select coalesce(
    (
      select
        (sum(case public.source_file_status(source_file) when 'PROCESSING' then 1 else 0 end)) >= public.source_file_parallel_processing_limit()
      from public.source_file
      where (
        source_file.added_by = (select id from private.current_user())
      ) and (
        source_file.client_company_id = client_company_source_file_parallel_processing_limit_reached.client_company.company_id
      )
    ),
    false
  )
$$
language sql stable strict;

comment on function public.client_company_source_file_parallel_processing_limit_reached is E'@notNull\nHas the parallel processing limit been reached for the current user in this client company.';
