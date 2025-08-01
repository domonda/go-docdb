create function rule.clone_action(
    id                                  uuid,
    client_company_id                   uuid = null,
    document_category_mapping           hstore = null, -- map[sourceID]destinationID
    document_workflow_step_mapping      hstore = null, -- map[sourceID]destinationID
    partner_company_mapping             hstore = null, -- map[sourceID]destinationID
    client_company_cost_center_mapping  hstore = null, -- map[sourceID]destinationID
    client_company_cost_unit_mapping    hstore = null, -- map[sourceID]destinationID
    real_estate_object_instance_mapping hstore = null  -- map[sourceID]destinationID
) returns rule.action as $$
declare
    source_action_id uuid := clone_action.id;
    cloned_action    rule.action;

    needs_attention     text[];
    needs_attention_all text[] := '{}';
begin
    insert into rule.action (client_company_id, name, description, created_by, updated_by)
        select
            coalesce(clone_action.client_company_id, action.client_company_id),
            action.name || case when clone_action.client_company_id is null then ' (copy)' else '' end,
            action.description,
            action.created_by,
            action.updated_by
        from rule.action where action.id = source_action_id
    returning * into cloned_action;
    if cloned_action is null then
        -- only if the action does not exist will the cloned one be null
        raise exception 'Action does not exist';
    end if;

    -- document_category
    if client_company_id is null -- cloning inside the same client
    or array_to_string(avals(document_category_mapping), '') <> '' -- if all values are null (or mapping is null), the string join will be an empty string
    then
        insert into rule.document_category_id_condition (action_id, document_category_id_equality, document_category_id, created_by, updated_by)
            select
                cloned_action.id,
                document_category_id_equality,
                case when client_company_id is not null and document_category_id is not null
                then coalesce((document_category_mapping->document_category_id::text)::uuid, '00000000-0000-0000-0000-000000000000')
                else document_category_id
                end,
                created_by,
                updated_by
            from rule.document_category_id_condition where action_id = source_action_id;
    else
        select array_agg(
            '•' || ' ' ||
            'document_category' || ' ' ||
            lower(document_category_id_equality::text) || ' ' ||
            coalesce(public.document_category_full_name(document_category, 'en'), 'EMPTY')
        ) into needs_attention
        from rule.document_category_id_condition
            left join public.document_category on document_category.id = document_category_id_condition.document_category_id
        where action_id = source_action_id;
        needs_attention_all := array_cat(needs_attention_all, needs_attention);
    end if;

    insert into rule.document_category_document_type_condition (action_id, document_type_equality, document_type, created_by, updated_by)
        select cloned_action.id, document_type_equality, document_type, created_by, updated_by
        from rule.document_category_document_type_condition where action_id = source_action_id;

    -- document
    insert into rule.document_condition (action_id, approved, created_by, updated_by)
        select cloned_action.id, approved, created_by, updated_by
        from rule.document_condition where action_id = source_action_id;

    insert into rule.document_import_date_condition (action_id, import_date_comparison, import_date, created_by, updated_by)
        select
            cloned_action.id,
            import_date_comparison,
            import_date,
            created_by,
            updated_by
        from rule.document_import_date_condition where action_id = source_action_id;

    if client_company_id is null -- cloning inside the same client
    or array_to_string(avals(document_workflow_step_mapping), '') <> '' -- if all values are null (or mapping is null), the string join will be an empty string
    then
        insert into rule.document_document_workflow_step_condition (action_id, document_workflow_step_id_equality, document_workflow_step_id, created_by, updated_by)
            select
                cloned_action.id,
                document_workflow_step_id_equality,
                case when client_company_id is not null and document_workflow_step_id is not null
                then coalesce((document_workflow_step_mapping->document_workflow_step_id::text)::uuid, '00000000-0000-0000-0000-000000000000')
                else document_workflow_step_id
                end,
                created_by,
                updated_by
            from rule.document_document_workflow_step_condition where action_id = source_action_id;
    else
        select array_agg(
            '•' || ' ' ||
            'document_workflow_step' || ' ' ||
            lower(document_workflow_step_id_equality::text) || ' ' ||
            coalesce(public.document_workflow_step_full_name(document_workflow_step), 'EMPTY')
        ) into needs_attention
        from rule.document_document_workflow_step_condition
            left join public.document_workflow_step on document_workflow_step.id = document_document_workflow_step_condition.document_workflow_step_id
        where action_id = source_action_id;
        needs_attention_all := array_cat(needs_attention_all, needs_attention);
    end if;

    insert into rule.document_approval_condition (action_id, approver_id, blank_approver_type)
        select cloned_action.id, approver_id, blank_approver_type
        from rule.document_approval_condition where action_id = source_action_id;

    if client_company_id is null -- cloning inside the same client
    or array_to_string(avals(real_estate_object_instance_mapping), '') <> '' -- if all values are null (or mapping is null), the string join will be an empty string
    then
        insert into rule.document_real_estate_object_condition (action_id, document_real_estate_object_instance_id_equality, document_real_estate_object_instance_id, created_by, updated_by)
            select
                cloned_action.id,
                document_real_estate_object_instance_id_equality,
                case when client_company_id is not null and document_real_estate_object_instance_id is not null
                then coalesce((real_estate_object_instance_mapping->document_real_estate_object_instance_id::text)::uuid, '00000000-0000-0000-0000-000000000000')
                else document_real_estate_object_instance_id
                end,
                created_by,
                updated_by
            from rule.document_real_estate_object_condition where action_id = source_action_id;
    else
        select array_agg(
            '•' || ' ' ||
            'document_real_estate_object' || ' ' ||
            lower(document_real_estate_object_instance_id_equality::text) || ' ' ||
            coalesce(public.real_estate_object_title((select real_estate_object from public.real_estate_object where real_estate_object.id = document_real_estate_object_condition.document_real_estate_object_instance_id)), 'EMPTY')
        ) into needs_attention
        from rule.document_real_estate_object_condition
        where action_id = source_action_id;
        needs_attention_all := array_cat(needs_attention_all, needs_attention);
    end if;

    -- invoice
    insert into rule.invoice_condition (action_id, created_by)
        select cloned_action.id, created_by
        from rule.invoice_condition where action_id = source_action_id;

    insert into rule.invoice_completeness_level_condition (action_id, completeness_level_equality, completeness_level, created_by, updated_by)
        select cloned_action.id, completeness_level_equality, completeness_level, created_by, updated_by
        from rule.invoice_completeness_level_condition where action_id = source_action_id;

    if client_company_id is null -- cloning inside the same client
    or array_to_string(avals(partner_company_mapping), '') <> '' -- if all values are null (or mapping is null), the string join will be an empty string
    then
        insert into rule.invoice_partner_company_condition (action_id, partner_company_id_equality, partner_company_id, created_by, updated_by)
            select
                cloned_action.id,
                partner_company_id_equality,
                case when client_company_id is not null and partner_company_id is not null
                then coalesce((partner_company_mapping->partner_company_id::text)::uuid, '00000000-0000-0000-0000-000000000000')
                else partner_company_id
                end,
                created_by,
                updated_by
            from rule.invoice_partner_company_condition where action_id = source_action_id;
    else
        select array_agg(
            '•' || ' ' ||
            'invoice_partner_company' || ' ' ||
            lower(partner_company_id_equality::text) || ' ' ||
            coalesce(partner_company.derived_name, 'EMPTY')
        ) into needs_attention
        from rule.invoice_partner_company_condition
            left join public.partner_company on partner_company.id = invoice_partner_company_condition.partner_company_id
        where action_id = source_action_id;
        needs_attention_all := array_cat(needs_attention_all, needs_attention);
    end if;

    insert into rule.invoice_total_condition (action_id, total_comparison, total, created_by, updated_by)
        select cloned_action.id, total_comparison, total, created_by, updated_by
        from rule.invoice_total_condition where action_id = source_action_id;

    insert into rule.invoice_invoice_date_condition (action_id, invoice_date_comparison, invoice_date, created_by, updated_by)
        select cloned_action.id, invoice_date_comparison, invoice_date, created_by, updated_by
        from rule.invoice_invoice_date_condition where action_id = source_action_id;

    if client_company_id is null -- cloning inside the same client
    or array_to_string(avals(client_company_cost_center_mapping), '') <> '' -- if all values are null (or mapping is null), the string join will be an empty string
    then
        insert into rule.invoice_cost_center_condition (action_id, client_company_cost_center_id_equality, client_company_cost_center_id, created_by, updated_by)
            select
                cloned_action.id,
                client_company_cost_center_id_equality,
                case when client_company_id is not null and client_company_cost_center_id is not null
                then coalesce((client_company_cost_center_mapping->client_company_cost_center_id::text)::uuid, '00000000-0000-0000-0000-000000000000')
                else client_company_cost_center_id
                end,
                created_by,
                updated_by
            from rule.invoice_cost_center_condition where action_id = source_action_id;
    else
        select array_agg(
            '•' || ' ' ||
            'invoice_cost_center' || ' ' ||
            lower(client_company_cost_center_id_equality::text) || ' ' ||
            coalesce(public.client_company_cost_center_full_name(client_company_cost_center), 'EMPTY')
        ) into needs_attention
        from rule.invoice_cost_center_condition
            left join public.client_company_cost_center on client_company_cost_center.id = invoice_cost_center_condition.client_company_cost_center_id
        where action_id = source_action_id;
        needs_attention_all := array_cat(needs_attention_all, needs_attention);
    end if;

    if client_company_id is null -- cloning inside the same client
    or array_to_string(avals(client_company_cost_unit_mapping), '') <> '' -- if all values are null (or mapping is null), the string join will be an empty string
    then
        insert into rule.invoice_cost_unit_condition (action_id, client_company_cost_unit_id_equality, client_company_cost_unit_id, created_by, updated_by)
            select
                cloned_action.id,
                client_company_cost_unit_id_equality,
                case when client_company_id is not null and client_company_cost_unit_id is not null
                then coalesce((client_company_cost_unit_mapping->client_company_cost_unit_id::text)::uuid, '00000000-0000-0000-0000-000000000000')
                else client_company_cost_unit_id
                end,
                created_by, updated_by
            from rule.invoice_cost_unit_condition where action_id = source_action_id;
    else
        select array_agg(
            '•' || ' ' ||
            'invoice_cost_unit' || ' ' ||
            lower(client_company_cost_unit_id_equality::text) || ' ' ||
            coalesce(public.client_company_cost_unit_full_name(client_company_cost_unit), 'EMPTY')
        ) into needs_attention
        from rule.invoice_cost_unit_condition
            left join public.client_company_cost_unit on client_company_cost_unit.id = invoice_cost_unit_condition.client_company_cost_unit_id
        where action_id = source_action_id;
        needs_attention_all := array_cat(needs_attention_all, needs_attention);
    end if;

    -- document_macro_condition
    insert into rule.document_macro_condition (
        action_id,
        macro,
        created_by,
        updated_by
    ) select
        cloned_action.id,
        macro,
        created_by,
        updated_by
    from rule.document_macro_condition where action_id = source_action_id;

    if array_length(needs_attention_all, 1) > 0
    then
        update rule.action
        set
            name=cloned_action.name || ' (NEEDS ATTENTION)',
            description=coalesce(cloned_action.description || E'\n\n', '') || E'Conditions that WERE NOT cloned:\n' || array_to_string(needs_attention_all, E'\n')
        where action.id = cloned_action.id;
    end if;

    return cloned_action;
end
$$ language plpgsql volatile;
