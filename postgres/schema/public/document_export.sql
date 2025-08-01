CREATE TABLE public.document_export (
    id                uuid PRIMARY KEY,
    client_company_id uuid NOT NULL REFERENCES public.client_company(company_id),
    user_id           uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- system-user ID for unknown user
        references public.user(id) on delete set default,

    filter_args           jsonb,
    populated_filter_args jsonb CHECK((filter_args IS NULL) = (populated_filter_args IS NULL)),

    until date, -- not used yet

    pdf_files             boolean NOT NULL DEFAULT false,
    spreadsheets          boolean NOT NULL DEFAULT false,
    bmd_bank              boolean NOT NULL DEFAULT false,
    bmd_masterdata        boolean NOT NULL DEFAULT false,
    bmd_invoices          boolean NOT NULL DEFAULT false,
    internal_bmd_invoices boolean NOT NULL DEFAULT false,
    dvo_invoices          boolean NOT NULL DEFAULT false,
    internal_dvo_invoices boolean NOT NULL DEFAULT false,
    im_factoring          boolean NOT NULL DEFAULT false,
    constraint require_one_export_flag CHECK(pdf_files OR spreadsheets OR bmd_invoices OR bmd_bank OR bmd_masterdata OR dvo_invoices OR internal_bmd_invoices OR internal_dvo_invoices OR im_factoring),

    CHECK (NOT (bmd_invoices AND internal_bmd_invoices)), -- not both cannot be true!
    constraint only_one_dvo_invoices CHECK (NOT (dvo_invoices AND internal_dvo_invoices)), -- not both cannot be true!

    booking_export boolean NOT NULL DEFAULT false,
    booking_period int, -- when null, use invoice months
    constraint booking_period_check check(booking_period > 0 and booking_period <= 12),

    created_at created_time NOT NULL
);

CREATE INDEX document_export_booking_export_idx ON public.document_export (booking_export);
CREATE INDEX document_export_client_company_id_idx ON public.document_export (client_company_id);
CREATE INDEX document_export_user_id_idx ON public.document_export (user_id);

COMMENT ON TABLE public.document_export IS 'Document exports';
GRANT SELECT, INSERT ON TABLE public.document_export TO domonda_user;
