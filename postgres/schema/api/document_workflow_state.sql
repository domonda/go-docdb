CREATE VIEW api.document_workflow_state WITH (security_barrier) AS 
SELECT 
	d.id AS document_id,
	dc.document_type AS document_type,
	dws.id AS workflow_step_id,
	dws.name AS workflow_step_name,
	dw.id AS workflow_id,
	dw.name AS workflow_name,
	dsc.state AS document_state,
	i.id AS signa_company_id,
	tp.value AS signa_company_name
FROM public.document d
LEFT JOIN public.document_category dc
	ON dc.id = d.category_id
LEFT JOIN public.document_workflow_step_log dwsl
	ON dwsl.document_id = d.id
LEFT JOIN public.document_workflow_step dws
	ON dws.id = dwsl.next_id
	AND dwsl.next_id NOT IN (
		SELECT prev_id FROM public.document_workflow_step
	)
LEFT JOIN public.document_workflow dw
	ON dw.id = dws.workflow_id
LEFT JOIN private.document_state_cache dsc
	ON dsc.document_id = d.id
-- signa company
LEFT JOIN public.document_real_estate_object dreo
	ON dreo.document_id = d.id
LEFT JOIN object.instance i
	ON i.id = dreo.object_instance_id
LEFT JOIN object.class_prop cp
	ON cp.class_name = 'SignaCompany' AND cp.name = 'Firmenname'
LEFT JOIN object.text_prop tp
	ON tp.class_prop_id = cp.id
	AND tp.instance_id = i.id;

COMMENT ON COLUMN api.document_workflow_state.document_type IS '@notNull';
COMMENT ON VIEW api.document_workflow_state IS $$
@primaryKey document_id
@foreignKey (document_id) REFERENCES api.document (id)
$$;

GRANT SELECT ON TABLE api.document_workflow_state TO domonda_api;