CREATE FUNCTION api.document_mutation()
RETURNS trigger AS
$$
BEGIN
    CASE TG_OP
        WHEN 'UPDATE' THEN
            IF NEW.workflow_step_id IS NOT DISTINCT FROM OLD.workflow_step_id
            THEN
                RETURN NEW;
            END IF;

            UPDATE public.document
                SET workflow_step_id=NEW.workflow_step_id, updated_at=now()
                WHERE (
                    id = NEW.id
                );

            INSERT INTO public.document_workflow_step_log (id, user_id, document_id, prev_id, next_id)
            VALUES (
                uuid_generate_v4(),
                'b2e0ed5c-b25a-4fee-854f-a33a4bc682f6', -- API
                NEW.id,
                OLD.workflow_step_id,
                NEW.workflow_step_id
            );

            RETURN NEW;
    END CASE;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER api_document_mutation_trigger INSTEAD OF UPDATE
    ON api.document
    FOR EACH ROW
    EXECUTE PROCEDURE api.document_mutation();

----

CREATE FUNCTION api.update_document(
    id               uuid,
    workflow_step_id uuid = NULL
) RETURNS api.document AS
$$
    UPDATE api.document SET workflow_step_id=update_document.workflow_step_id WHERE (id = update_document.id)
    RETURNING api.document.*
$$
LANGUAGE SQL VOLATILE;

COMMENT ON FUNCTION api.update_document IS 'Updates a `Document`.';
