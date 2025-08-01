CREATE TABLE public.scanner (
  id                uuid PRIMARY KEY,
  client_company_id uuid REFERENCES public.client_company(company_id) ON DELETE CASCADE,

  name text NOT NULL,

  created_at created_time NOT NULL
);

COMMENT ON TABLE public.scanner IS 'A physical scanner owned by a company.';
GRANT SELECT, UPDATE ON TABLE public.scanner TO domonda_user;

----

CREATE TABLE public.scan (
    id           uuid PRIMARY KEY,
    scanner_id   uuid NOT NULL REFERENCES public.scanner(id) ON DELETE CASCADE,

    user_id uuid NOT NULL REFERENCES public.user(id),

    active boolean NOT NULL DEFAULT false,

    document_category_id uuid NOT NULL REFERENCES public.document_category(id),
    period_date          timestamptz,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

COMMENT ON TABLE public.scan IS 'A scan process of a scanner initialized by the user.';
GRANT SELECT, UPDATE, INSERT ON TABLE public.scan TO domonda_user;

CREATE UNIQUE INDEX scan_active_unique ON public.scan (scanner_id, active) WHERE (active);

----

CREATE TABLE public.scan_item (
  id      uuid PRIMARY KEY,
  scan_id uuid NOT NULL REFERENCES public.scan(id) ON DELETE CASCADE,

  document_id uuid REFERENCES public.document(id) ON DELETE CASCADE,

  -- item metadata go here --

  created_at created_time NOT NULL
);

COMMENT ON TABLE public.scan_item IS 'A single scan item from a scan process.';
GRANT SELECT, UPDATE, INSERT ON TABLE public.scan_item TO domonda_user;
