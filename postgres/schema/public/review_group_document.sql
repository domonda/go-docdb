---- document ----

create table public.review_group_document (
  id              uuid primary key default uuid_generate_v4(),
  review_group_id uuid not null references public.review_group(id) on delete cascade,

  source_document_id uuid unique references public.document(id) on delete restrict, -- null indicates a new document
  constraint unique_document_check unique(source_document_id), -- guarantees document can be in 1 review group globally at a time

  -- where is this document positioned in the review group
  sort_index int not null,
  constraint sort_index_check check(sort_index >= 0),
  -- deferrable initially deferred checks the constraint on transaction commit, helps simplify the sorting functions
  constraint document_sort_index_uniqueness unique(sort_index, review_group_id) deferrable initially deferred,

  -- things user wishes to change (if fields stay null, don't change anything)
  deleted                   boolean not null default false,
  document_category_id      uuid not null references public.document_category(id) on delete restrict,
  document_workflow_step_id uuid references public.document_workflow_step(id) on delete restrict,
  tags                      text[], -- will be created for the client company if not existing
  -- more to be added...

  updated_at updated_time not null,
  created_at created_time not null
);

grant all on table public.review_group_document to domonda_user;
grant select on table public.review_group_document to domonda_wg_user; -- TODO: other grants

create index review_group_document_review_group_id_idx on public.review_group_document (review_group_id);
create index review_group_document_source_document_id_idx on public.review_group_document (source_document_id);

comment on column public.review_group_document.sort_index is '@omit';

----

create function public.review_group_document_new(
  review_group_document public.review_group_document
) returns boolean as
$$
  select review_group_document.source_document_id is null
$$
language sql immutable strict;

comment on function public.review_group_document_new is E'@notNull\nIs a new document.';

----

create function public.review_group_sorted_documents(
  review_group public.review_group
) returns setof public.review_group_document as
$$
  select * from public.review_group_document
  where review_group_id = review_group.id
  order by sort_index asc
$$
language sql stable strict;

----

create function public.update_review_group_document(
  id                        uuid,
  deleted                   boolean,
  document_category_id      uuid,
  document_workflow_step_id uuid = null,
  tags                      text[] = null
) returns public.review_group_document as
$$
  with updated_review_group_document as (
    update public.review_group_document set
      deleted=update_review_group_document.deleted,
      document_category_id=update_review_group_document.document_category_id,
      document_workflow_step_id=update_review_group_document.document_workflow_step_id,
      tags=update_review_group_document.tags,
      updated_at=now()
    where id = update_review_group_document.id
    returning *
  )
  update public.review_group set
    updated_by=(select id from private.current_user()),
    updated_at=now()
  from updated_review_group_document
  where review_group.id = updated_review_group_document.review_group_id
  returning updated_review_group_document.*
$$
language sql volatile;

comment on function public.update_review_group_document is '@notNull';

----

create function public.update_review_group_documents(
  review_group_id                  uuid,
  deleted                          boolean = null,
  document_category_id             uuid = null,
  clear_document_workflow_step_ids boolean = false,
  document_workflow_step_id        uuid = null,
  clear_tags                       boolean = false,
  tags                             text[] = null
) returns setof public.review_group_document as
$$
  with updated_review_group as (
    update public.review_group set
      updated_by=(select id from private.current_user()),
      updated_at=now()
    where review_group.id = update_review_group_documents.review_group_id
    returning 1
  )
  update public.review_group_document set
    deleted=coalesce(
      update_review_group_documents.deleted,
      review_group_document.deleted
    ),
    document_category_id=coalesce(
      update_review_group_documents.document_category_id,
      review_group_document.document_category_id
    ),
    document_workflow_step_id=(
      case update_review_group_documents.clear_document_workflow_step_ids
        when true then null
        else coalesce(
          update_review_group_documents.document_workflow_step_id,
          review_group_document.document_workflow_step_id
        )
      end
    ),
    tags=(
      case update_review_group_documents.clear_tags
        when true then null
        else coalesce(
          update_review_group_documents.tags,
          review_group_document.tags
        )
      end
    ),
    updated_at=now()
  from updated_review_group -- just to trigger the update
  where review_group_id = update_review_group_documents.review_group_id
  returning review_group_document.*
$$
language sql volatile;

comment on function public.update_review_group_documents is E'@notNull\nUpdates all documents belonging to the review group.';

---- page ----

create table public.review_group_document_page (
  id                       uuid primary key default uuid_generate_v4(),
  review_group_document_id uuid not null references public.review_group_document(id) on delete cascade,

  source_document_id         uuid not null references public.document(id) on delete restrict,
  source_document_page_index int not null check(source_document_page_index >= 0),

  -- where is this page positioned in the document
  sort_index int not null,
  constraint sort_index_check check(sort_index >= 0),
  -- deferrable initially deferred checks the constraint on transaction commit, helps simplify the sorting functions
  constraint page_sort_index_uniqueness unique(sort_index, review_group_document_id) deferrable initially deferred,

  -- useful for tracking pages when you close the page preview dialog
  label text,
  constraint label_check check(length(label) > 0 and length(label) <= 32),

  -- things user wishes to change
  deleted    boolean not null default false,
  attachment boolean not null default false,
  constraint deleted_attachment_check check(not (deleted and attachment)), -- cannot marked as deleted and an attachment in the same time

  rotation int not null default 0,
  constraint rotation_check check(
    case rotation
      when 0 then true
      when 90 then true
      when 180 then true
      when 270 then true
      else false
    end
  ),

  updated_at updated_time not null,
  created_at created_time not null
);

grant select, update on table public.review_group_document_page to domonda_user;

create index review_group_document_page_review_group_document_id_idx on public.review_group_document_page (review_group_document_id);

comment on column public.review_group_document_page.sort_index is '@omit';

----

create function public.split_all_pages_of_review_group_document(
  review_group_document_id uuid
) returns setof public.review_group_document as
$$
declare
  source_doc     public.review_group_document;
  next_doc_index int;
  min_page_index int;
  page_ids       uuid[];
  page_id        uuid;
  new_doc_id     uuid;
begin
  select * into source_doc
    from public.review_group_document
    where id = review_group_document_id;

  select min(p.sort_index) into min_page_index
    from public.review_group_document_page as p
    where p.review_group_document_id = source_doc.id
      and p.deleted = false;

  select coalesce(array_agg(p.id order by sort_index), '{}') into page_ids
    from public.review_group_document_page as p
    where p.review_group_document_id = source_doc.id
      and p.sort_index > min_page_index
      and p.deleted = false
      and p.attachment = false;

  select max(sort_index) + 1 into next_doc_index
    from public.review_group_document
    where review_group_id = source_doc.review_group_id;

  foreach page_id in array page_ids loop
    new_doc_id := uuid_generate_v4();

    insert into
      public.review_group_document (
        id,
        review_group_id,
        source_document_id,
        sort_index,
        document_category_id,
        document_workflow_step_id,
        tags
      )
      values (
        new_doc_id,                           -- id
        source_doc.review_group_id,           -- review_group_id,
        null::uuid,                           -- source_document_id,
        next_doc_index,                       -- sort_index,
        source_doc.document_category_id,      -- document_category_id,
        source_doc.document_workflow_step_id, -- document_workflow_step_id,
        source_doc.tags                       -- tags
      );

    update public.review_group_document_page
      set
        review_group_document_id =new_doc_id,
        sort_index               =0,
        deleted                  =false,
        attachment               =false,
        updated_at               =now()
      where id = page_id;

    next_doc_index := next_doc_index + 1;
  end loop;

  return query
    select *
    from public.review_group_document
    where review_group_id = source_doc.review_group_id
    order by sort_index;
end
$$ language plpgsql volatile;

comment on function public.split_all_pages_of_review_group_document is E'Splits all pages starting with the second one of a document into new documents and returns all documents of the group';

----

create function public.review_group_document_page_validate_change() returns trigger as $$
declare
  v_review_group_id uuid;
  v_next_page       public.review_group_document_page;
begin
  if TG_OP = 'INSERT' OR TG_OP = 'UPDATE' then
    v_next_page = NEW;
  else
    v_next_page = OLD;
  end if;

  -- find belonging review group
  select
    rgd.review_group_id into v_review_group_id
  from public.review_group_document as rgd
    inner join public.review_group_document_page as rgdp on rgdp.review_group_document_id = rgd.id
  where rgdp.id = v_next_page.id;

  -- non-owner users cannot change the URL
  if (
    TG_OP = 'UPDATE'
  ) and (
    session_user = 'domonda_user'
  ) and (
    (
      OLD.source_document_id is distinct from v_next_page.source_document_id
    ) or (
      OLD.source_document_page_index is distinct from v_next_page.source_document_page_index
    )
  ) then
    raise exception 'You cannot change the source document of the page';
  end if;

  -- TODO-db-200424 this is checked BEFORE the event and can be false-positive
  -- check if all pages of a document are attachments
  -- if exists (
  --   select from public.review_group_document_page as rgdp
  --     inner join public.review_group_document as rgd on rgd.id = rgdp.review_group_document_id
  --   where rgd.review_group_id = v_review_group_id
  --   group by rgdp.review_group_document_id
  --   -- number of pages equals number of attachments
  --   having count(rgdp) = sum(case rgdp.attachment when true then 1 else 0 end)
  -- ) then
  --   raise exception 'At least one non-attachment page must exist in a document';
  -- end if;

  return v_next_page;
end;
$$ language plpgsql stable;

create trigger review_group_document_page_validate_change
  before insert or update or delete on public.review_group_document_page
  for each row execute procedure public.review_group_document_page_validate_change();

----

create function public.review_group_document_sorted_pages(
  review_group_document public.review_group_document
) returns setof public.review_group_document_page as
$$
  select * from public.review_group_document_page
  where review_group_document_id = review_group_document.id
  order by sort_index asc
$$
language sql stable strict;

----

create function public.update_review_group_document_page(
  id         uuid,
  deleted    boolean,
  attachment boolean,
  rotation   int,
  label      text = null
) returns public.review_group_document_page as
$$
  with updated_review_group_document_page as (
    update public.review_group_document_page set
      deleted=update_review_group_document_page.deleted,
      attachment=update_review_group_document_page.attachment,
      rotation=update_review_group_document_page.rotation,
      label=update_review_group_document_page.label,
      updated_at=now()
    where id = update_review_group_document_page.id
    returning *
  )
  update public.review_group set
    updated_by=(select id from private.current_user()),
    updated_at=now()
  from updated_review_group_document_page
    inner join public.review_group_document as rgd on rgd.id = updated_review_group_document_page.review_group_document_id
  where review_group.id = rgd.review_group_id
  returning updated_review_group_document_page.*
$$
language sql volatile;

comment on function public.update_review_group_document_page is '@notNull';

----

create function public.review_group_document_count(
  review_group public.review_group
) returns bigint as
$$
  select count(*)
  from public.review_group_document
  where review_group_id = review_group_document_count.review_group.id
$$
language sql stable strict;

comment on function public.review_group_document_count is '@notNull';
