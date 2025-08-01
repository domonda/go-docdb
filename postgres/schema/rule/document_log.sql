CREATE TABLE rule.document_log (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    action_reaction_id  uuid NOT NULL REFERENCES rule.action_reaction(id) ON DELETE CASCADE,
    document_id         uuid NOT NULL REFERENCES public.document(id) ON DELETE CASCADE,

    created_at created_time NOT NULL
);

-- NOTE: domonda user shouldn't be able to INSERT!
GRANT INSERT, SELECT ON rule.document_log TO domonda_user;
grant select on rule.document_log to domonda_wg_user;

CREATE INDEX document_log_action_reaction_id_document_id_idx ON rule.document_log (action_reaction_id, document_id);
CREATE INDEX document_log_action_reaction_id_idx ON rule.document_log (action_reaction_id);
CREATE INDEX document_log_document_id_idx ON rule.document_log (document_id);
