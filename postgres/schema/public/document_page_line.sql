CREATE TABLE public.document_page_line (
    id     uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    id_ext text, -- Optional ID from OCR or some other text extraction

	page_id  uuid NOT NULL REFERENCES public.document_page(id) ON DELETE CASCADE,
    block_id uuid REFERENCES public.document_page_block(id) ON DELETE SET NULL,

    bbox box NOT NULL,

	updated_at updated_time NOT NULL,
	created_at created_time NOT NULL
);

COMMENT ON TYPE public.document_page_line IS 'Text line on a document page';
GRANT SELECT ON TABLE public.document_page_line TO domonda_user;

create index document_page_line_page_id_idx on public.document_page_line(page_id);
create index document_page_line_block_id_idx on public.document_page_line(block_id);
