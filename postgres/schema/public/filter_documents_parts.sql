-- useful for any form of documents filtering, the function's cost is set to be
-- high which forces the planner to execute the function before others leading to
-- much better performance when having other complex indexes mixed in (like fulltext)
create function public.filter_documents_of_client_company(
  client_company_id uuid
) returns setof public.document as $$
  select * from public.document where document.client_company_id = filter_documents_of_client_company.client_company_id
  -- not locked by a review group
  and not exists (select from public.review_group_document
      inner join public.review_group on review_group.id = review_group_document.review_group_id
  where review_group_document.source_document_id = document.id
  and review_group.documents_lock_id is not null)
  -- a "more" correct check is `public.document_is_visual`. however, we expect all visual documents to have pages
  and document.num_pages > 0
$$ language sql stable strict
cost 10000;

create function public.filter_documents_of_client_company_and_fulltext(
  client_company_id uuid,
  search_text       text
) returns setof public.document as $$
  select * from public.document where document.client_company_id = filter_documents_of_client_company_and_fulltext.client_company_id
  -- not locked by a review group
  and not exists (select from public.review_group_document
      inner join public.review_group on review_group.id = review_group_document.review_group_id
  where review_group_document.source_document_id = document.id
  and review_group.documents_lock_id is not null)
  -- a "more" correct check is `public.document_is_visual`. however, we expect all visual documents to have pages
  and document.num_pages > 0
  and (searchtext @@ plainto_tsquery('german', filter_documents_of_client_company_and_fulltext.search_text)
    or (fulltext_w_invoice ilike '%' || filter_documents_of_client_company_and_fulltext.search_text || '%'))
$$ language sql stable strict
cost 10000;

create function public.filter_documents_of_client_company_and_fulltext_only_ts(
  client_company_id uuid,
  search_text       text
) returns setof public.document as $$
  select * from public.document where document.client_company_id = filter_documents_of_client_company_and_fulltext_only_ts.client_company_id
  -- not locked by a review group
  and not exists (select from public.review_group_document
      inner join public.review_group on review_group.id = review_group_document.review_group_id
  where review_group_document.source_document_id = document.id
  and review_group.documents_lock_id is not null)
  -- a "more" correct check is `public.document_is_visual`. however, we expect all visual documents to have pages
  and document.num_pages > 0
  and searchtext @@ plainto_tsquery('german', filter_documents_of_client_company_and_fulltext_only_ts.search_text)
$$ language sql stable strict
cost 10000;
