create function public.filter_document_categories(
  client_company_id uuid,
  search_text       text = null
) returns setof public.document_category as $$
  select * from public.document_category
  where filter_document_categories.client_company_id = document_category.client_company_id
  -- omit deprecated and non-visual document types
  and not (document_category.document_type = any('{BANK_STATEMENT,CREDITCARD_STATEMENT,FACTORING_STATEMENT,DOCUMENT_EXPORT_FILE,BANK_EXPORT_FILE,ACL_IMPORT_FILE,CREDITCARD_IMPORT_FILE,BANK_ACCOUNT_IMPORT_FILE}'))
  and (
    (coalesce(trim(filter_document_categories.search_text), '') = '')
    or (
      public.document_category_full_name(document_category, 'en') ilike '%' || filter_document_categories.search_text || '%'
      or (public.document_category_full_name(document_category, 'de') ilike '%' || filter_document_categories.search_text || '%')
      or (document_category.email_alias ilike '%' || filter_document_categories.search_text || '%')
    )
  )
  order by
    sort_index,
    document_type desc,
    booking_type desc,
    booking_category desc,
    description desc
$$ language sql stable;

----

create function public.filter_protected_document_categories(
  client_company_id uuid,
  search_text       text = null
) returns setof public.document_category as $$
  select * from public.filter_document_categories(
    filter_protected_document_categories.client_company_id,
    filter_protected_document_categories.search_text
  )
$$ language sql stable security definer;
