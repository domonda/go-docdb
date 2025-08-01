CREATE TABLE rule.invoice_log (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    action_reaction_id  uuid NOT NULL REFERENCES rule.action_reaction(id) ON DELETE CASCADE,
    invoice_document_id uuid NOT NULL REFERENCES public.invoice(document_id) ON DELETE CASCADE,

    created_at created_time NOT NULL
);

-- NOTE: domonda user shouldn't be able to INSERT!
GRANT INSERT, SELECT ON rule.invoice_log TO domonda_user;
grant select on rule.invoice_log to domonda_wg_user;

CREATE INDEX invoice_log_action_reaction_id_invoice_document_id_idx ON rule.invoice_log (action_reaction_id, invoice_document_id);
CREATE INDEX invoice_log_action_reaction_id_idx ON rule.invoice_log (action_reaction_id);
CREATE INDEX invoice_log_invoice_document_id_idx ON rule.invoice_log (invoice_document_id);
