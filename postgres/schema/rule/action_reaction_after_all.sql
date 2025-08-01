create function rule.actions_reactions_by_client_company_id(
    client_company_id uuid
) returns setof rule.action_reaction as
$$
    select ar.* from rule.action_reaction as ar
        inner join rule.action as a on (a.id = ar.action_id)
        inner join (
            rule.reaction as r
            left join rule.document_approval_request_reaction as document_approval_request_reaction on document_approval_request_reaction.reaction_id = r.id
            left join rule.send_mail_document_workflow_changed_reaction on send_mail_document_workflow_changed_reaction.reaction_id = r.id
        ) on (r.id = ar.reaction_id)
    where (
        a.client_company_id = actions_reactions_by_client_company_id.client_company_id
    ) and (
        r.client_company_id = actions_reactions_by_client_company_id.client_company_id
    )
    order by
        -- respect the sort_index
        sort_index desc,
        -- approval requests should be first to react so that workflow interactions can be built
        document_approval_request_reaction nulls last,
        -- notifications go last so that all mutations on the invoice can happen first
        send_mail_document_workflow_changed_reaction nulls first
$$
language sql stable strict;

create function rule.action_reaction_was_triggered(
    action_reaction rule.action_reaction
) returns boolean as $$
    select exists(select from rule.send_mail_document_workflow_changed_log
        where send_mail_document_workflow_changed_log.action_reaction_id = action_reaction.id)
    or exists(select from rule.send_notification_log
        where send_notification_log.action_reaction_id = action_reaction.id)
    or exists(select from rule.document_log
        where document_log.action_reaction_id = action_reaction.id)
    or exists(select from rule.invoice_log
        where invoice_log.action_reaction_id = action_reaction.id)
    or exists(select from rule.document_approval_request_log
        where document_approval_request_log.action_reaction_id = action_reaction.id)
    or exists(select from rule.cancel_document_approval_request_log
        where cancel_document_approval_request_log.action_reaction_id = action_reaction.id)
    or exists(select from rule.document_macro_log
        where document_macro_log.action_reaction_id = action_reaction.id)
$$ language sql stable strict;
comment on function rule.action_reaction_was_triggered is '@notNull';
