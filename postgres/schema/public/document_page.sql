CREATE TABLE public.document_page (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

	document_version_id uuid NOT NULL REFERENCES docdb.document_version(id) ON DELETE CASCADE,
    index               int NOT NULL CHECK(index >= 0),
    UNIQUE(document_version_id, index),

    is_attachment boolean NOT NULL DEFAULT false,
    image         text NOT NULL CHECK(length(image) >= 5), -- Min example: length('0.png') == 5
    image_width   int NOT NULL CHECK(image_width > 0),
    image_height  int NOT NULL CHECK(image_height > 0),
    
    width  float8 NOT NULL CHECK(width > 0),
    height float8 NOT NULL CHECK(height > 0),
    dpi    float8 CHECK(dpi > 0),

    ocr boolean NOT NULL,

    -- text_hash text REFERENCES public.document_page_text(hash),

	updated_at updated_time NOT NULL,
	created_at created_time NOT NULL
);

COMMENT ON TYPE public.document_page IS 'Document version page extraction information';
GRANT SELECT ON TABLE public.document_page TO domonda_user;

create index document_page_document_version_id_idx on public.document_page(document_version_id);
