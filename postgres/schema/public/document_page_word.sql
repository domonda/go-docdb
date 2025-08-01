CREATE TABLE public.document_page_word (
    id     uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    id_ext text, -- Optional ID from OCR or some other text extraction

	page_id  uuid NOT NULL REFERENCES public.document_page(id) ON DELETE CASCADE,
    block_id uuid REFERENCES public.document_page_block(id) ON DELETE SET NULL,
    line_id  uuid REFERENCES public.document_page_line(id) ON DELETE SET NULL,

    bbox box NOT NULL,
    word text NOT NULL CHECK(length(word) > 0),

	updated_at updated_time NOT NULL,
	created_at created_time NOT NULL
);

COMMENT ON TYPE public.document_page_word IS 'Word on a document page';
GRANT SELECT ON TABLE public.document_page_word TO domonda_user;

create index document_page_word_page_id_idx on public.document_page_word(page_id);
create index document_page_word_block_id_idx on public.document_page_word(block_id);
create index document_page_word_line_id_idx on public.document_page_word(line_id);
