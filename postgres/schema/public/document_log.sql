create type public.document_log_type as enum (
  'ADDED_TO_REVIEW',
  'REMOVED_FROM_REVIEW',
  'ARCHIVED',
  'UNARCHIVED',
  'DELETED',
  'RESTORED',
  'SHARE',
  'REVOKE_SHARE',
  'CLONED',
  'DERIVED',
  'OVERRIDE_PARTNER_PAYMENT_PRESET',
  'CATEGORY_CHANGED'
  -- NOTE: dont forget to add new values to document_history_type enum!
);

create table public.document_log (
  id uuid primary key default uuid_generate_v4(),

  "type"      public.document_log_type not null,
  document_id uuid not null references public.document(id) on delete cascade,

  user_id uuid not null
    default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
    references public.user(id) on delete set default,

  review_group_id uuid references public.review_group(id) on delete set null,

  share_user_id uuid
    default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
    references public.user(id) on delete set default,

  prev_category_id uuid references public.document_category(id) on delete set null,
  next_category_id uuid references public.document_category(id) on delete set null,

  created_at created_time not null
);

grant select on table public.document_log to domonda_user;

create index document_log_type_idx on public.document_log ("type");
create index document_log_document_id_idx on public.document_log (document_id);
create index document_log_user_id_idx on public.document_log (user_id);
create index document_log_review_group_id_idx on public.document_log (review_group_id);
create index document_log_share_user_id_idx on public.document_log (share_user_id);
create index document_log_prev_category_id_idx on public.document_log (prev_category_id);
create index document_log_next_category_id_idx on public.document_log (next_category_id);

----

create function private.document_log_archived_or_unarchived()
returns trigger as $$
begin
  if private.current_user_id() is null
  then
    return null;
  end if;

  insert into public.document_log ("type", document_id, user_id)
  values ((case when new.archived then 'ARCHIVED' else 'UNARCHIVED' end)::public.document_log_type, new.id, private.current_user_id());

  return null;
end
$$ language plpgsql volatile security definer;

create trigger document_archived_or_unarchived
    after update on public.document
    for each row
    when (old.archived is distinct from new.archived)
    execute function private.document_log_archived_or_unarchived();
