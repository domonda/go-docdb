create function public.filter_user_groups(
  client_company_id uuid,
  search_text text = null
) returns setof public.user_group as $$
  select * from public.user_group
  where filter_user_groups.client_company_id = user_group.client_company_id
  and (
    (coalesce(trim(filter_user_groups.search_text), '') = '')
    or (
      (user_group.name ilike '%' || filter_user_groups.search_text || '%')
    )
  )
  order by name desc
$$ language sql stable;
