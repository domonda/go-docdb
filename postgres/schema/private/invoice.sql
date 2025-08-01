CREATE FUNCTION private.invoice_exists(
	document_id uuid
) RETURNS boolean AS
$$
	SELECT EXISTS (SELECT 1 FROM public.invoice WHERE (document_id = invoice_exists.document_id) LIMIT 1)
$$
LANGUAGE SQL STABLE SECURITY DEFINER COST 100000;

----

CREATE FUNCTION private.invoice_client_company_id(
    document_id uuid
) RETURNS uuid AS
$$
    SELECT client_company_id FROM public.document WHERE (id = invoice_client_company_id.document_id) LIMIT 1
$$
LANGUAGE SQL STABLE SECURITY DEFINER COST 100000;
