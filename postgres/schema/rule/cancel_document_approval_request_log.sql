create table rule.cancel_document_approval_request_log (
    id uuid primary key default uuid_generate_v4(),

    action_reaction_id  uuid not null references rule.action_reaction(id) on delete cascade,
    document_id         uuid not null references public.document(id) on delete cascade,

    created_at created_time not null
);

-- note: domonda user shouldn't be able to insert!
grant insert, select on rule.cancel_document_approval_request_log to domonda_user;
grant select on rule.cancel_document_approval_request_log to domonda_wg_user;

create index cancel_document_approval_request_log_action_reaction_id_document_id_idx on rule.cancel_document_approval_request_log (action_reaction_id, document_id);
create index cancel_document_approval_request_log_action_reaction_id_idx on rule.cancel_document_approval_request_log (action_reaction_id);
create index cancel_document_approval_request_log_document_id_idx on rule.cancel_document_approval_request_log (document_id);
