create type public.document_state as enum (
  'READY',
  'CHECKED_OUT',
  'LOCKED',
  'IN_RESTRUCTURE_GROUP',
  'PROCESSING',
  'ACCOUNTANT_LOCK',
  'BOOKED',
  'BOOKING_CANCELED', -- was in a booking export, but was removed
  'READY_FOR_BOOKING',
  'DELETED',
  'SUPERSEDED'
  -- TODO add 'ARCHIVED'
);

comment on type public.document_state is 'Document states.';

create table private.document_state_cache (
  document_id uuid primary key references public.document(id) on delete cascade,
  state       public.document_state not null, -- see private.derive_document_state
  reason      trimmed_text not null, -- reason for caching the state, usually the "<TG_NAME>-<TG_OP>"
  updated_at  updated_time not null
);

create index document_state_cache_state_idx on private.document_state_cache (state);

grant select on table private.document_state_cache to domonda_user;
grant select on table private.document_state_cache to domonda_wg_user;

create function private.derive_document_state(
  document_id uuid
) returns public.document_state as $$
declare
  state public.document_state;
begin
  if docdb.is_document_processing(document_id)
  then
    return 'PROCESSING';
  end if;

  -- important to know when to allow a user to change the document, like applying a review group
  -- locked by a review group
  if exists (select from public.review_group_document
      inner join public.review_group on review_group.id = review_group_document.review_group_id
    where review_group_document.source_document_id = document_id
    and review_group.documents_lock_id is not null)
  then
    return 'IN_RESTRUCTURE_GROUP';
  end if;

  if (select checkout_user_id is not null from public.document where document.id = document_id)
  then
    return 'CHECKED_OUT';
  end if;

  if docdb.is_document_locked(document_id)
  then
    return 'LOCKED';
  end if;

  if (select superseded from public.document where document.id = document_id)
  then
    return 'DELETED';
  end if;

  if (select invoice.booked_at is not null from public.invoice
    where invoice.document_id = derive_document_state.document_id)
  then
    return 'BOOKED';
  end if;

  if exists (select from public.export_document
      inner join public.export on export.id = export_document.export_id
    where export_document.document_id = derive_document_state.document_id
    and export_document.removed_at is null
    and export.booking_export)
  then
    return 'BOOKED';
  end if;

  if (select removed_at is not null from public.export_document
      inner join public.document on document.id = derive_document_state.document_id
      inner join public.export on export.id = export_document.export_id
    where export_document.document_id = derive_document_state.document_id
    and export.client_company_id = document.client_company_id
    and export.booking_export
    order by export.created_at desc
    limit 1)
  then
    return 'BOOKING_CANCELED';
  end if;

  if exists (select from public.export_document
      inner join public.export on export.id = export_document.export_id
    where export_document.document_id = derive_document_state.document_id
    and export.ready_for_booking_export
    and export_document.removed_at is null)
  then
    return 'READY_FOR_BOOKING';
  end if;

  return 'READY';
end
$$ language plpgsql stable strict
security definer; -- user mustn't have access to all the internals but still can derive the state

----

create function private.cache_document_state() returns trigger as $$
declare
  tg_table text := (tg_table_schema || '.' || tg_table_name);
  new_or_old record;
  caching_reason text := (tg_name || '-' || tg_op);
  caching_document_id uuid;
begin
  if tg_op = 'DELETE'
  then
    new_or_old = old;
  else
    new_or_old = new;
  end if;

  case tg_table
  when 'public.document' then
    caching_document_id = new_or_old.id;
  when 'public.invoice' then
    caching_document_id = new_or_old.document_id;
  when 'docdb.locked_document' then
    caching_document_id = new_or_old.document_id;
  when 'public.export_document' then
    caching_document_id = new_or_old.document_id;
  when 'public.review_group_document' then
    caching_document_id = new_or_old.source_document_id;
    if caching_document_id is null
    then
      return null; -- beware to always use the AFTER trigger
    end if;
  when 'public.review_group' then
    -- update state cache of each document in the review group and exit
    for caching_document_id in (
      select source_document_id
      from public.review_group_document
      where review_group_document.review_group_id = new_or_old.id
      and source_document_id is not null
    ) loop
      insert into private.document_state_cache (document_id, state, reason)
      values (caching_document_id, private.derive_document_state(caching_document_id), caching_reason)
      on conflict (document_id) do update set
        state=private.derive_document_state(caching_document_id),
        reason=caching_reason,
        updated_at=now();
    end loop;
    return null;
  else
    raise exception 'Unexpected trigger table %', tg_table;
  end case;

  insert into private.document_state_cache (document_id, state, reason)
  values (caching_document_id, private.derive_document_state(caching_document_id), caching_reason)
  on conflict (document_id) do update set
    state=private.derive_document_state(caching_document_id),
    reason=caching_reason,
    updated_at=now();

  return null; -- beware to always use the AFTER trigger
end
$$ language plpgsql volatile strict
security definer; -- user mustn't have access to all the internals but still can derive the state

create trigger cache_document_state_document_insert
  after insert on public.document
  for each row
  execute procedure private.cache_document_state();

create trigger cache_document_state_document_checkout_user_update
  after update on public.document
  for each row
  when (old.checkout_user_id is distinct from new.checkout_user_id)
  execute procedure private.cache_document_state();

create trigger cache_document_state_document_superseded_update
  after update on public.document
  for each row
  when (old.superseded is distinct from new.superseded)
  execute procedure private.cache_document_state();

create trigger cache_document_state_invoice_booked_at_update
  after update on public.invoice
  for each row
  when (old.booked_at is distinct from new.booked_at)
  execute procedure private.cache_document_state();

-- TODO: will the invoice ever be booked on insert? currently we only listen for updates

create trigger cache_document_state_docdb_lock
  after insert or delete on docdb.locked_document
  for each row
  execute procedure private.cache_document_state();

create trigger cache_document_state_review_group_document
  after insert or delete on public.review_group_document
  for each row
  execute procedure private.cache_document_state();

create trigger cache_document_state_review_group_insert
  after insert on public.review_group
  for each row
  execute procedure private.cache_document_state();

create trigger cache_document_state_review_group_lock_update
  after update on public.review_group
  for each row
  when (old.documents_lock_id is distinct from new.documents_lock_id)
  execute procedure private.cache_document_state();

create trigger cache_document_state_export_document
  after insert or update or delete on public.export_document
  for each row
  execute procedure private.cache_document_state();

-- TODO: do we need to listen for public.export changes? by the looks of it - no

----

create function public.document_state(
  document public.document
) returns public.document_state as $$
declare
  cached_state public.document_state;
begin
  select state into cached_state
  from private.document_state_cache
  where document_state_cache.document_id = document.id;

  if cached_state is null
  then
    cached_state := private.derive_document_state(document.id);
    -- TODO: inserts can not be done in non-volatile functions
    -- insert into private.document_state_cache (document_id, state)
    -- values (document.id, cached_state);
  end if;

  return cached_state;
end
$$ language plpgsql stable strict;

comment on function public.document_state is
e'@notNull\nDerived state (or status) of the `Document`.';

----

create function private.update_document_state(
  doc_id uuid
) returns public.document_state as $$
  insert into private.document_state_cache (document_id, state, reason)
  values (doc_id, private.derive_document_state(doc_id), 'update_document_state')
  on conflict (document_id) do update set
    state=private.derive_document_state(doc_id),
    reason='update_document_state',
    updated_at=now()
  returning state
$$ language sql volatile strict;