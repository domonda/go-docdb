create type public.review_group_document_sort as (
  review_group_document_id       uuid, -- null indicates a new document
  review_group_document_page_ids uuid[]
);
comment on column public.review_group_document_sort.review_group_document_page_ids is '@notNull';

create function public.sort_review_group(
  id             uuid,
  document_sorts public.review_group_document_sort[]
) returns public.review_group as
$$
declare
  review_group public.review_group;
  new_review_group_document_id uuid;
  i int;
  j int;
begin
  -- ensures the review group exists and the row is locked
  select
    rg.* into review_group
  from public.review_group as rg
  where rg.id = sort_review_group.id
  for update nowait;
  if review_group is null then
    raise exception 'Review group % does not exist', sort_review_group.id;
  end if;

  -- validate the sorts by checking if the total counts fit,
  -- all documents belong to the review group and all pages
  -- belong to the documents in the review group. besides
  -- doing the actual validation, the rows are locked
  if coalesce((
    select
      -- we make a subquery because FOR UPDATE is not allowed with aggregate functions
      count(1) <> (
        -- count of total pages in the sorts
        select
          sum(array_length(document_sort.review_group_document_page_ids, 1))
        from unnest(document_sorts) as document_sort
      )
    from (
      select 1 from
        public.review_group_document as rgd
          inner join public.review_group_document_page as rgdp on rgdp.review_group_document_id = rgd.id,
        unnest(document_sorts) as document_sort
      where (
        rgd.review_group_id = review_group.id
      -- allows moving pages between documents
      -- ) and (
      --   rgd.id = document_sort.review_group_document_id
      ) and (
        rgdp.id = any(document_sort.review_group_document_page_ids)
      )
      for update nowait
    ) as temp
  ), true) then
    raise exception 'Invalid document sorts argument';
  end if;

  -- sort documents
  for i in 1 .. coalesce(array_upper(document_sorts, 1), 1) loop
    if document_sorts[i].review_group_document_id is null then
      -- new document only if has pages
      if document_sorts[i].review_group_document_page_ids[1] is not null then
        insert into public.review_group_document (review_group_id, sort_index, document_category_id, document_workflow_step_id, tags)
          values (
            review_group.id, 
            i-1, -- indices start at zero
            ( -- set category to dragging source document
              select rgd.document_category_id from public.review_group_document as rgd
                inner join public.review_group_document_page as rgdp on rgdp.review_group_document_id = rgd.id
              where rgdp.id = document_sorts[i].review_group_document_page_ids[1]
            ),
            ( -- set workflow step to dragging source document
              select rgd.document_workflow_step_id from public.review_group_document as rgd
                inner join public.review_group_document_page as rgdp on rgdp.review_group_document_id = rgd.id
              where rgdp.id = document_sorts[i].review_group_document_page_ids[1]
            ),
            ( -- set tags to dragging source document
              select rgd.tags from public.review_group_document as rgd
                inner join public.review_group_document_page as rgdp on rgdp.review_group_document_id = rgd.id
              where rgdp.id = document_sorts[i].review_group_document_page_ids[1]
            )
          )
        returning review_group_document.id into new_review_group_document_id;
      end if;
    else
      -- existing document
      update public.review_group_document set
        sort_index=i-1, -- indices start at zero
        updated_at=now()
      where review_group_document.id = document_sorts[i].review_group_document_id;
    end if;

    -- sort pages
    for j in 1 .. coalesce(array_upper(document_sorts[i].review_group_document_page_ids, 1), 1) loop
      update public.review_group_document_page set
        review_group_document_id=coalesce(document_sorts[i].review_group_document_id, new_review_group_document_id),
        sort_index=j-1, -- indices start at zero
        updated_at=now()
      where review_group_document_page.id = document_sorts[i].review_group_document_page_ids[j];
    end loop;
  end loop;

  -- remove all new review group documents without pages
  delete from public.review_group_document as rgd
  where (
    rgd.review_group_id = review_group.id
  ) and (
    rgd.source_document_id is null
  ) and (
    not exists (select 1 from public.review_group_document_page as rgdp where rgdp.review_group_document_id = rgd.id)
  );

  -- update updated_at info on the group itself
  update public.review_group as rg set
    updated_by=(select cu.id from private.current_user() as cu),
    updated_at=now()
  where rg.id = review_group.id
  returning
    rg.* into review_group;

  return review_group;
end
$$
language plpgsql volatile strict;

comment on function public.sort_review_group is '@notNull\nSorts the given `ReviewGroup` documents and their pages atomically using the `reviewGroupDocumentSort` model.';
