-- NOTE: If the trigger function raises an exception, so does the UPDATE. Meaning that the UPDATE is not applied!
-- This is nifty because if the users action cannot be logged, he also cannot perform the said action (allows consistency in logs).

CREATE FUNCTION private.notify_update_document_workflow_step_id() RETURNS trigger AS
$$
BEGIN
    -- Only authenticated user actions should be logged.
    -- The only case when the user does not have a `current_user_id` set is when he is the db owner.
    IF NOT private.current_setting_flag('current.disable_document_workflow_step_logging')
    AND private.current_user_id() IS NOT NULL
    THEN
        INSERT INTO public.document_workflow_step_log (id, user_id, document_id, prev_id, next_id)
            VALUES (uuid_generate_v4(), private.current_user_id(), NEW.id, OLD.workflow_step_id, NEW.workflow_step_id);
    END IF;

    RETURN NEW;
END;
$$
LANGUAGE plpgsql;

----

CREATE TRIGGER document_workflow_step_trigger AFTER UPDATE ON public.document
    FOR EACH ROW WHEN (OLD.workflow_step_id IS DISTINCT FROM NEW.workflow_step_id)
    EXECUTE PROCEDURE private.notify_update_document_workflow_step_id();
