CREATE TYPE public.email_attachment_status AS ENUM (
    'CREATED',
    'GET_ERROR',
    'DOCUMENT_EXISTS',
    'IMPORT_ERROR',
    'IMPORTED'
);

COMMENT ON TYPE public.email_attachment_status IS 'Status of the attachment';

----

CREATE TABLE public.email_attachment (
    id          text PRIMARY KEY,
    internal_id text UNIQUE,
    email_id    text NOT NULL REFERENCES public.email(id) ON DELETE CASCADE,
    document_id uuid REFERENCES public.document(id) ON DELETE CASCADE,

    status      public.email_attachment_status NOT NULL,

    file_name   text NOT NULL,
    file_size   integer NOT NULL,
    file_type   text NOT NULL,

    updated_at  updated_time NOT NULL,
    created_at  created_time NOT NULL
);

-- ALTER TABLE email_attachment ALTER COLUMN internal_id DROP NOT NULL;

COMMENT ON TABLE public.email_attachment IS 'Information or importing documents from an email account';

GRANT SELECT ON TABLE public.email_attachment TO domonda_user;
