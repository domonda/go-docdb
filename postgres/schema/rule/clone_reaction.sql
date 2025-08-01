create function rule.clone_reaction(
    id                             uuid,
    client_company_id              uuid = null,
    document_workflow_step_mapping hstore = null, -- map[sourceID]destinationID
    client_company_tag_mapping     hstore = null, -- map[sourceID]destinationID
    user_group_mapping             hstore = null -- map[sourceID]destinationID
) returns rule.reaction as $$
declare
    source_reaction_id uuid := clone_reaction.id;
    cloned_reaction    rule.reaction;

    needs_attention     text[];
    needs_attention_all text[] := '{}';
begin
    insert into rule.reaction (client_company_id, name, description, created_by, updated_by)
    select
        coalesce(clone_reaction.client_company_id, reaction.client_company_id),
        reaction.name || case when clone_reaction.client_company_id is null then ' (copy)' else '' end,
        reaction.description,
        reaction.created_by,
        reaction.updated_by
    from rule.reaction where reaction.id = source_reaction_id
    returning * into cloned_reaction;
    if cloned_reaction is null then
        -- only if the reaction does not exist will the cloned one be null
        raise exception 'Reaction does not exist';
    end if;

    -- send_mail_document_workflow_changed
    insert into rule.send_mail_document_workflow_changed_reaction (reaction_id, user_id, created_by, updated_by)
    select cloned_reaction.id, user_id, created_by, updated_by
    from rule.send_mail_document_workflow_changed_reaction where reaction_id = source_reaction_id;

    -- document
    if client_company_id is null -- cloning inside the same client
    or array_to_string(avals(document_workflow_step_mapping), '') <> '' -- if all values are null (or mapping is null), the string join will be an empty string
    then
        insert into rule.document_reaction (reaction_id, change_workflow_step_id, workflow_step_id, created_by, updated_by)
        select
            cloned_reaction.id,
            change_workflow_step_id,
            case when client_company_id is not null and workflow_step_id is not null
            then coalesce((document_workflow_step_mapping->workflow_step_id::text)::uuid, '00000000-0000-0000-0000-000000000000')
            else workflow_step_id
            end,
            created_by,
            updated_by
        from rule.document_reaction where reaction_id = source_reaction_id;
    else
        select array_agg(
            '•' || ' ' ||
            'document' || ' ' ||
            case change_workflow_step_id when true then 'workflow step change to' else 'workflow step DONT change to' end || ' ' ||
            coalesce(public.document_workflow_step_full_name(document_workflow_step), 'EMPTY')
        ) into needs_attention
        from rule.document_reaction
            left join public.document_workflow_step on document_workflow_step.id = document_reaction.workflow_step_id
        where reaction_id = source_reaction_id;
        needs_attention_all := array_cat(needs_attention_all, needs_attention);
    end if;

    -- invoice
    insert into rule.invoice_reaction (
        reaction_id,
        change_currency,
        currency,
        change_payment_status,
        payment_status,
        change_due_date_from_invoice_date_in_days,
        due_date_from_invoice_date_in_days,
        change_discount_percent,
        discount_percent,
        change_discount_until_from_invoice_date_in_days,
        discount_until_from_invoice_date_in_days,
        change_iban,
        iban,
        change_bic,
        bic,
        created_by,
        updated_by
    ) select
        cloned_reaction.id,
        change_currency,
        currency,
        change_payment_status,
        payment_status,
        change_due_date_from_invoice_date_in_days,
        due_date_from_invoice_date_in_days,
        change_discount_percent,
        discount_percent,
        change_discount_until_from_invoice_date_in_days,
        discount_until_from_invoice_date_in_days,
        change_iban,
        iban,
        change_bic,
        bic,
        created_by,
        updated_by
    from rule.invoice_reaction where reaction_id = source_reaction_id;

    -- document_approval
    -- first clone all reactions that dont require no mapping
    insert into rule.document_approval_request_reaction (
        reaction_id,
        blank_approver_count,
        blank_approver_type,
        approver_id,
        controller_user_from_document_partner_company,
        message,
        created_by,
        updated_by
    ) select
        cloned_reaction.id,
        blank_approver_count,
        blank_approver_type,
        approver_id,
        controller_user_from_document_partner_company,
        message,
        created_by,
        updated_by
    from rule.document_approval_request_reaction
    where reaction_id = source_reaction_id
    and user_group_id is null;
    -- then clone the reactions that need a mapping
    if client_company_id is null -- cloning inside the same client
        or array_to_string(avals(user_group_mapping), '') <> '' -- if all values are null (or mapping is null), the string join will be an empty string
    then
        insert into rule.document_approval_request_reaction (reaction_id, user_group_id, message, created_by, updated_by)
            select
                cloned_reaction.id,
                case when client_company_id is not null and user_group_id is not null
                then coalesce((user_group_mapping->user_group_id::text)::uuid, '00000000-0000-0000-0000-000000000000')
                else user_group_id
                end,
                message,
                created_by,
                updated_by
            from rule.document_approval_request_reaction
            where reaction_id = source_reaction_id
            and user_group_id is not null;
    else
        select array_agg(
            '•' || ' ' ||
            'document approval request to user group' || ' ' ||
            user_group.name
        ) into needs_attention
        from rule.document_approval_request_reaction
            left join public.user_group on user_group.id = document_approval_request_reaction.user_group_id
        where reaction_id = source_reaction_id
        and user_group_id is not null;
        needs_attention_all := array_cat(needs_attention_all, needs_attention);
    end if;

    -- send_notification
    insert into rule.send_notification_reaction (
        reaction_id,
        destination,
        receiver_user_id,
        receiver_email,
        receiver_url,
        note,
        created_by,
        updated_by
    ) select
        cloned_reaction.id,
        destination,
        receiver_user_id,
        receiver_email,
        receiver_url,
        note,
        created_by,
        updated_by
    from rule.send_notification_reaction where reaction_id = source_reaction_id;

    -- document_tag
    if client_company_id is null -- cloning inside the same client
        or array_to_string(avals(client_company_tag_mapping), '') <> '' -- if all values are null (or mapping is null), the string join will be an empty string
    then
        insert into rule.document_tag_reaction (reaction_id, client_company_tag_id, created_by, updated_by)
        select
            cloned_reaction.id,
            case when client_company_id is not null and client_company_tag_id is not null
                then
                    coalesce((client_company_tag_mapping->client_company_tag_id::text)::uuid, '00000000-0000-0000-0000-000000000000')
                else
                    client_company_tag_id
            end,
            created_by,
            updated_by
        from rule.document_tag_reaction where reaction_id = source_reaction_id;
    else
        select array_agg(
            '•' || ' ' ||
            'document_tag set' || ' ' ||
            client_company_tag.tag
        ) into needs_attention
        from rule.document_tag_reaction
            left join public.client_company_tag on client_company_tag.id = document_tag_reaction.client_company_tag_id
        where reaction_id = source_reaction_id;
        needs_attention_all := array_cat(needs_attention_all, needs_attention);
    end if;

    -- document_macro_reaction
    insert into rule.document_macro_reaction (
        reaction_id,
        macro,
        created_by,
        updated_by
    ) select
        cloned_reaction.id,
        macro,
        created_by,
        updated_by
    from rule.document_macro_reaction where reaction_id = source_reaction_id;

    if array_length(needs_attention_all, 1) > 0
    then
        update rule.reaction
        set
            name=cloned_reaction.name || ' (NEEDS ATTENTION)',
            description=coalesce(cloned_reaction.description || E'\n\n', '') || E'Reactions that WERE NOT cloned:\n' || array_to_string(needs_attention_all, E'\n')
        where reaction.id = cloned_reaction.id;
    end if;

    return cloned_reaction;
end
$$ language plpgsql volatile;
