CREATE TABLE public.document_workflow_step_log (
    id      uuid PRIMARY KEY,

    user_id     uuid NOT NULL REFERENCES public.user(id) ON DELETE CASCADE,
    document_id uuid NOT NULL REFERENCES public.document(id) ON DELETE CASCADE,

    prev_id uuid REFERENCES public.document_workflow_step(id) ON DELETE CASCADE,
    next_id uuid REFERENCES public.document_workflow_step(id) ON DELETE CASCADE,

    created_at created_time NOT NULL
);

GRANT SELECT, INSERT ON TABLE public.document_workflow_step_log TO domonda_user;
grant select on public.document_workflow_step_log to domonda_wg_user;

CREATE INDEX document_workflow_step_log_user_id_idx ON public.document_workflow_step_log (user_id);
CREATE INDEX document_workflow_step_log_document_id_idx ON public.document_workflow_step_log (document_id);
CREATE INDEX document_workflow_step_log_prev_id_idx ON public.document_workflow_step_log (prev_id);
CREATE INDEX document_workflow_step_log_next_id_idx ON public.document_workflow_step_log (next_id);
CREATE INDEX document_workflow_step_log_created_at_idx ON public.document_workflow_step_log (created_at);

----

CREATE FUNCTION public.document_workflow_step_log_protected_prev_workflow_step_full_name(
    document_workflow_step_log public.document_workflow_step_log
) RETURNS text AS
$$
    SELECT public.document_workflow_step_full_name(document_workflow_step) FROM public.document_workflow_step
    WHERE id = document_workflow_step_log.prev_id
$$
LANGUAGE SQL STABLE SECURITY DEFINER;

COMMENT ON FUNCTION public.document_workflow_step_log_protected_prev_workflow_step_full_name IS '@fieldName protectedPrevWorkflowStepFullName';

----

CREATE FUNCTION public.document_workflow_step_log_protected_next_workflow_step_full_name(
    document_workflow_step_log public.document_workflow_step_log
) RETURNS text AS
$$
    SELECT public.document_workflow_step_full_name(document_workflow_step) FROM public.document_workflow_step
    WHERE id = document_workflow_step_log.next_id
$$
LANGUAGE SQL STABLE SECURITY DEFINER;

COMMENT ON FUNCTION public.document_workflow_step_log_protected_next_workflow_step_full_name IS '@fieldName protectedNextWorkflowStepFullName';
