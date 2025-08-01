CREATE FUNCTION api.client_company_tag_mutation()
RETURNS trigger AS
$$
BEGIN
    CASE TG_OP
        WHEN 'INSERT' THEN
            INSERT INTO public.client_company_tag (id, client_company_id, tag) VALUES (
                NEW.id,
                (SELECT api.current_client_company_id()),
                NEW.name
            );

            RETURN NEW;
        WHEN 'DELETE' THEN
            IF NOT EXISTS (SELECT 1 FROM api.client_company_tag WHERE (id = OLD.id)) THEN
                RAISE EXCEPTION 'ClientCompanyTag "%" not found', OLD.id;
            END IF;

            DELETE FROM public.client_company_tag WHERE (id = OLD.id);

            RETURN OLD;
        WHEN 'UPDATE' THEN
            IF NOT EXISTS (SELECT 1 FROM api.client_company_tag WHERE (id = NEW.id)) THEN
                RAISE EXCEPTION 'ClientCompanyTag "%" not found', NEW.id;
            END IF;

            UPDATE public.client_company_tag
                SET tag=NEW.name
                WHERE (
                    id = NEW.id
                );

            RETURN NEW;
    END CASE;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER api_company_tag_mutation_trigger INSTEAD OF INSERT OR DELETE OR UPDATE
    ON api.client_company_tag
    FOR EACH ROW
    EXECUTE PROCEDURE api.client_company_tag_mutation();

----

CREATE FUNCTION api.create_client_company_tag(
    name text
) RETURNS api.client_company_tag AS
$$
    INSERT INTO api.client_company_tag (id, name)
        VALUES (uuid_generate_v4(), create_client_company_tag.name)
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

COMMENT ON FUNCTION api.create_client_company_tag IS 'Creates a `ClientCompanyTag`.';

----

CREATE FUNCTION api.delete_client_company_tag(
    id uuid
) RETURNS api.client_company_tag AS
$$
    DELETE FROM api.client_company_tag WHERE (id = delete_client_company_tag.id)
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

COMMENT ON FUNCTION api.delete_client_company_tag IS 'Deletes a `ClientCompanyTag`.';

----

CREATE FUNCTION api.update_client_company_tag(
    id   uuid,
    name text
) RETURNS api.client_company_tag AS
$$
    UPDATE api.client_company_tag SET name=update_client_company_tag.name WHERE (id = update_client_company_tag.id)
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

COMMENT ON FUNCTION api.update_client_company_tag IS 'Updates a `ClientCompanyTag`.';
