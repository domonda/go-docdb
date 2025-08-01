CREATE FUNCTION api.partner_company_mutation()
RETURNS trigger AS
$$
BEGIN
    CASE TG_OP
        WHEN 'INSERT' THEN
            RAISE EXCEPTION 'Creating a PartnerCompany from the API is not allowed';
        WHEN 'DELETE' THEN
            RAISE EXCEPTION 'Deleting a PartnerCompany from the API is not allowed';
        WHEN 'UPDATE' THEN
            IF NOT EXISTS (SELECT FROM api.partner_company WHERE (id = NEW.id)) THEN
                RAISE EXCEPTION 'PartnerCompany "%" not found', NEW.id;
            END IF;

            NEW.disabled_by = case when NEW.active then null else 'b2e0ed5c-b25a-4fee-854f-a33a4bc682f6' end; -- API
            NEW.disabled_at = case when NEW.active then null else now() end;

            UPDATE public.partner_company
                SET
                    disabled_by=NEW.disabled_by,
                    disabled_at=NEW.disabled_at,
                    updated_at=now()
                WHERE (
                    id = NEW.id
                );

            RETURN NEW;
    END CASE;
END;
$$
LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER api_partner_company_mutation_trigger INSTEAD OF INSERT OR DELETE OR UPDATE
    ON api.partner_company
    FOR EACH ROW
    EXECUTE PROCEDURE api.partner_company_mutation();

CREATE FUNCTION api.update_partner_company(
    id     uuid,
    active boolean
) RETURNS api.partner_company AS
$$
    UPDATE api.partner_company SET active=update_partner_company.active WHERE (id = update_partner_company.id)
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

COMMENT ON FUNCTION api.update_partner_company IS 'Updates a `PartnerCompany`.';
