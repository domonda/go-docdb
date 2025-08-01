CREATE FUNCTION public.client_company_users_with_access(
    client_company public.client_company
) RETURNS SETOF public.user AS
$$
    SELECT u.* FROM public.user AS u
        INNER JOIN control.client_company_user AS ccu ON ((ccu.user_id = u.id) AND (ccu.client_company_id = client_company_users_with_access.client_company.company_id))
    WHERE (u.type <> 'SYSTEM')
$$
LANGUAGE SQL STABLE;

COMMENT ON FUNCTION public.client_company_users_with_access(public.client_company) IS 'Users who have access to the client company';
GRANT EXECUTE ON FUNCTION public.client_company_users_with_access(public.client_company) TO domonda_user;
