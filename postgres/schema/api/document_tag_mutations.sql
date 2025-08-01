CREATE FUNCTION api.document_tag_mutation()
RETURNS trigger AS
$$
DECLARE
    input RECORD;
BEGIN
    -- extract
    input := COALESCE(OLD, NEW);

    -- validate
    IF NOT EXISTS (SELECT 1 FROM api.document WHERE (id = input.document_id)) THEN
        RAISE EXCEPTION 'Document "%" not found', input.document_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM api.client_company_tag WHERE (id = input.client_company_tag_id)) THEN
        RAISE EXCEPTION 'ClientCompanyTag "%" not found', input.client_company_tag_id;
    END IF;

    -- perform
    CASE TG_OP
        WHEN 'INSERT' THEN
            INSERT INTO public.document_tag (client_company_tag_id, document_id) VALUES (
                input.client_company_tag_id,
                input.document_id
            );

            RETURN input;
        WHEN 'DELETE' THEN
            DELETE FROM public.document_tag WHERE (
                document_id = input.document_id
            ) AND (
                client_company_tag_id = input.client_company_tag_id
            );

            RETURN input;
    END CASE;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER api_document_tag_mutation_trigger INSTEAD OF INSERT OR DELETE
    ON api.document_tag
    FOR EACH ROW
    EXECUTE PROCEDURE api.document_tag_mutation();

----

CREATE FUNCTION api.create_document_tag(
    client_company_tag_id uuid,
    document_id           uuid
) RETURNS api.document_tag AS
$$
    INSERT INTO api.document_tag (client_company_tag_id, document_id)
        VALUES (create_document_tag.client_company_tag_id, create_document_tag.document_id)
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

COMMENT ON FUNCTION api.create_document_tag IS 'Creates a `DocumentTag`.';

----

CREATE FUNCTION api.delete_document_tag(
    client_company_tag_id uuid,
    document_id           uuid
) RETURNS api.document_tag AS
$$
    DELETE FROM api.document_tag WHERE (
        document_id = delete_document_tag.document_id
    ) AND (
        client_company_tag_id = delete_document_tag.client_company_tag_id
    )
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

COMMENT ON FUNCTION api.delete_document_tag IS 'Deletes a `DocumentTag`.';
