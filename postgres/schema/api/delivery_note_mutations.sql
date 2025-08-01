-- CREATE FUNCTION api.delivery_note_mutation()
-- RETURNS trigger AS
-- $$
-- BEGIN
--     CASE TG_OP
--         WHEN 'UPDATE' THEN
--             IF NOT EXISTS (SELECT 1 FROM api.delivery_note WHERE (id = NEW.id)) THEN
--                 RAISE EXCEPTION 'DeliveryNote "%" not found', NEW.id;
--             END IF;

--             UPDATE public.delivery_note
--                 SET invoice_id=NEW.invoice_document_id
--                 WHERE (
--                     document_id = NEW.document_id
--                 );

--             RETURN NEW;
--     END CASE;
-- END;
-- $$
-- LANGUAGE plpgsql SECURITY DEFINER;

-- CREATE TRIGGER api_delivery_note_mutation_trigger INSTEAD OF UPDATE
--     ON api.delivery_note
--     FOR EACH ROW
--     EXECUTE PROCEDURE api.delivery_note_mutation();

-- ----

-- CREATE FUNCTION api.update_delivery_note(
--     document_id         uuid,
--     invoice_document_id uuid = NULL
-- ) RETURNS api.delivery_note AS
-- $$
--     UPDATE api.delivery_note SET invoice_document_id=update_delivery_note.invoice_document_id WHERE (document_id = update_delivery_note.document_id)
--     RETURNING api.delivery_note.*
-- $$
-- LANGUAGE SQL VOLATILE;

-- COMMENT ON FUNCTION api.update_delivery_note IS 'Updates a `DeliveryNote` with the `documentId`.';
