CREATE TABLE rule.send_mail_document_workflow_changed_log(
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    action_reaction_id uuid NOT NULL REFERENCES rule.action_reaction(id) ON DELETE CASCADE,
    document_id        uuid NOT NULL REFERENCES public.document(id) ON DELETE CASCADE,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

-- NOTE: domonda user shouldn't be able to INSERT!
GRANT INSERT, SELECT ON rule.send_mail_document_workflow_changed_log TO domonda_user;
grant select on rule.send_mail_document_workflow_changed_log to domonda_wg_user;

CREATE INDEX send_mail_document_workflow_changed_log_action_reaction_id_document_id_idx ON rule.send_mail_document_workflow_changed_log (action_reaction_id, document_id);
CREATE INDEX send_mail_document_workflow_changed_log_action_reaction_id_idx ON rule.send_mail_document_workflow_changed_log (action_reaction_id);
CREATE INDEX send_mail_document_workflow_changed_log_document_id_idx ON rule.send_mail_document_workflow_changed_log (document_id);
