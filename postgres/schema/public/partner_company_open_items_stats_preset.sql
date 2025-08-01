CREATE TABLE public.partner_company_open_items_stats_preset (
    id uuid PRIMARY KEY,

    client_company_id uuid NOT NULL REFERENCES public.client_company(company_id) ON DELETE CASCADE,
    "name"            text NOT NULL CHECK(length("name") > 1), -- at least 2 characters
    UNIQUE(client_company_id, "name"),

    "filter" public.partner_company_open_items_stats_filter NOT NULL,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT SELECT, UPDATE, INSERT, DELETE ON public.partner_company_open_items_stats_preset TO domonda_user;

CREATE INDEX partner_company_open_items_stats_preset_client_company_id_idx ON public.partner_company_open_items_stats_preset (client_company_id);
CREATE INDEX partner_company_open_items_stats_preset_name_idx ON public.partner_company_open_items_stats_preset (name);

----

CREATE FUNCTION public.partner_company_open_items_stats_presets_by_client_company_id(
    client_company_id uuid
) RETURNS SETOF public.partner_company_open_items_stats_preset AS
$$
    SELECT * FROM public.partner_company_open_items_stats_preset WHERE (client_company_id = partner_company_open_items_stats_presets_by_client_company_id.client_company_id)
$$
LANGUAGE SQL STABLE STRICT;
