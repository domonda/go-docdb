CREATE VIEW api.document_workflow_step WITH (security_barrier) AS
    SELECT 
        dws.id,
        dws.workflow_id,
        dws.name,
        dws.updated_at,
        dws.created_at
    FROM public.document_workflow_step AS dws
        INNER JOIN api.document_workflow AS dw ON (dw.id = dws.workflow_id);

GRANT SELECT ON TABLE api.document_workflow_step to domonda_api;

COMMENT ON COLUMN api.document_workflow_step.workflow_id IS '@notNull';
COMMENT ON COLUMN api.document_workflow_step.name IS '@notNull';
COMMENT ON VIEW api.document_workflow_step IS $$
@primaryKey id
@foreignKey (workflow_id) references api.document_workflow (id)
A `DocumentWorkflowStep` is a step which belongs to a `DocumentWorkflow`. A `Document` can be in a single `DocumentWorkflowStep` at a time.$$;
