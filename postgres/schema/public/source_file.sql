create type public.source_file_origin as enum (
  'PARENT_SOURCE_FILE', -- if the source file gives more files (archives, email files)
  'UPLOAD',
  'EMAIL',
  'GET_MY_INVOICES',
  'API'
);

-- destination of the arriving file
create type public.source_file_category as enum (
  'DOCUMENT',
  'UPDATE_DOCUMENT',
  'MONEY_TRANSACTIONS'
);

create table public.source_file (
  id uuid primary key default uuid_generate_v4(),

  origin   public.source_file_origin not null check(parent_source_file_id is null or origin = 'PARENT_SOURCE_FILE'), -- origin must be the parent file when the parent file is provided
  added_by uuid not null
    default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- system-user ID for unknown user
    references public.user(id) on delete set default,
  client_company_id  uuid not null references public.client_company(company_id) on delete cascade,

  name text     not null check(length(trim(name)) > 0),
  size int      not null check(size > 0), -- no empty files
  hash char(64) not null check(length(hash) = 64), -- SHA-256 32byte value

  category public.source_file_category not null,
  metadata json not null,
  constraint metadata_for_document_category check (
    category <> 'DOCUMENT'
    or (
      public.is_valid_uuid(metadata->>'documentCategoryId')
    )
  ),
  constraint metadata_for_update_document_category check (
    category <> 'UPDATE_DOCUMENT'
    or (
      public.is_valid_uuid(metadata->>'updateDocumentId')
    )
  ),
  constraint metadata_for_money_transactions_category check (
    category <> 'MONEY_TRANSACTIONS'
    or (
      metadata->>'moneyTransactionsType' = 'BANK'
      or metadata->>'moneyTransactionsType' = 'CREDIT_CARD'
    )
  ),

  review_group_id uuid references public.review_group(id) on delete restrict,

  processing_started_at timestamptz,
  processing_ended_at   timestamptz,
  processing_percentage int check(processing_percentage >= 0 and processing_percentage <= 100), -- null means processing has not started yet
  processing_error      text check(length(processing_error) > 0), -- user friendly error message during processing

  parent_source_file_id uuid references public.source_file(id) on delete cascade,
  -- we cascade document ids because when processing is completed the file gets MOVED to the documents dir
  resulting_document_id uuid references public.document(id) on delete cascade, -- resulting document after processing is completed
  duplicate_document_id uuid references public.document(id) on delete cascade, -- detected duplicate document
  constraint document_review_group_and_result_check check(
    case category
      when 'DOCUMENT' then (
        (
          (
            -- both are empty
            resulting_document_id is null and duplicate_document_id is null
          ) and (
            -- review group reference must exist
            review_group_id is not null
          )
        ) or (
          (
            -- only one is set
            (resulting_document_id is null) <> (duplicate_document_id is null)
          ) and (
            -- review group reference must not exist
            review_group_id is null
          )
        )
      )
      when 'UPDATE_DOCUMENT' then (
        -- review group reference must not exist ever
        review_group_id is null
        and (
          -- both are empty
          (resulting_document_id is null and duplicate_document_id is null)
          -- or only one is set
          or (resulting_document_id is null) <> (duplicate_document_id is null)
        )
      )
      -- MONEY_TRANSACTIONS work differently
      else true
    end
  ),

  updated_at updated_time not null,
  created_at created_time not null
);

grant select on public.source_file to domonda_user;
grant select on public.source_file to domonda_wg_user;

create unique index source_file_only_one_updating_document
  on public.source_file ((metadata->>'updateDocumentId'))
  where (category = 'UPDATE_DOCUMENT'
    and resulting_document_id is null);

create unique index source_file_hash_unique_processing_for_client
  on public.source_file (client_company_id, hash)
  where (resulting_document_id is null);

create index source_file_hash_idx on public.source_file (hash);
create index source_file_added_by_idx on public.source_file (added_by);
create index source_file_client_company_id_idx on public.source_file (client_company_id);
create index source_file_category_idx on public.source_file (category);
create index source_file_metadata_update_document_id_idx on public.source_file ((metadata->>'updateDocumentId'));
create index source_file_resulting_document_id_idx on public.source_file (resulting_document_id);
create index source_file_duplicate_document_id_idx on public.source_file (duplicate_document_id);

----

create function public.source_file_document_category_from_metadata(
  source_file public.source_file
) returns public.document_category as
$$
  select * from public.document_category where id = (source_file.metadata->>'documentCategoryId')::uuid
$$
language sql stable strict;

----

create function public.source_file_money_transactions_type_from_metadata(
  source_file public.source_file
) returns text as
$$
  select source_file.metadata->>'moneyTransactionsType'
$$
language sql immutable strict;

----

create function public.source_file_update_document_from_metadata(
  source_file public.source_file
) returns public.document as
$$
  select * from public.document where id = (source_file.metadata->>'updateDocumentId')::uuid
$$
language sql stable strict;

create function public.document_updating_document_source_file(
  document public.document
) returns public.source_file as $$
  select * from public.source_file
  -- see source_file_only_one_updating_document index
  where (source_file.metadata->>'updateDocumentId')::uuid = document.id
  and source_file.category = 'UPDATE_DOCUMENT'
  and resulting_document_id is null
$$ language sql stable strict;

----

create function public.source_file_parallel_processing_limit() returns int as
$$
  select 50
$$
language sql immutable;

comment on function public.source_file_parallel_processing_limit is E'@notNull\nNumber of files allowed to be processed in parallel by user in client company.';
