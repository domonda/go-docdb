-- can return:
    -- null: no document checks are present
    -- true: document check passed, perform reaction
    -- false: document check hasent passed, no reaction
create function rule.document_check(
    action  rule.action,
    document public.document
) returns boolean as
$$
declare
    -- initially the OK value is true because we AND the conditions
    ok boolean := true;
    -- conditionals
    document_condition                         rule.document_condition; -- can be only one per action
    document_client_company_tag_conditions     rule.document_client_company_tag_condition[];
    document_import_date_conditions            rule.document_import_date_condition[];
    document_document_workflow_step_conditions rule.document_document_workflow_step_condition[];
    document_approval_conditions               rule.document_approval_condition[];
    document_real_estate_object_conditions     rule.document_real_estate_object_condition[];
    condition                                  record;
    condition_result                           boolean := false;
begin
    -- find document condition
    select
        * into document_condition
    from rule.document_condition where action_id = action.id;

    -- find document import date conditions
    SELECT
        array_agg(c) INTO document_import_date_conditions
    FROM rule.document_import_date_condition AS c
    WHERE (c.action_id = action.id);

    -- find document client-company-tag conditions
    SELECT
        array_agg(c) INTO document_client_company_tag_conditions
    FROM rule.document_client_company_tag_condition AS c
    WHERE (c.action_id = action.id);

    -- find document workflow step conditions
    SELECT
        array_agg(c) INTO document_document_workflow_step_conditions
    FROM rule.document_document_workflow_step_condition AS c
    WHERE (c.action_id = action.id);

    -- find document approval conditions
    SELECT
        array_agg(c) INTO document_approval_conditions
    FROM rule.document_approval_condition AS c
    WHERE (c.action_id = action.id);

    -- find document real-estate-object conditions
    SELECT
        array_agg(c) INTO document_real_estate_object_conditions
    FROM rule.document_real_estate_object_condition AS c
    WHERE (c.action_id = action.id);

    -- if there are no conditions, return null
    IF (
        document_condition is null
    ) AND (
        coalesce(array_length(document_import_date_conditions, 1), 0) = 0
    ) AND (
        coalesce(array_length(document_client_company_tag_conditions, 1), 0) = 0
    ) AND (
        coalesce(array_length(document_document_workflow_step_conditions, 1), 0) = 0
    ) AND (
        coalesce(array_length(document_approval_conditions, 1), 0) = 0
    ) AND (
        coalesce(array_length(document_real_estate_object_conditions, 1), 0) = 0
    ) THEN

        RETURN null;

    END IF;

    -- if document does not exist, conditions cannot pass
    IF document IS NULL
    THEN
        RETURN false;
    END IF;

    -- check document condition
    if not (document_condition is null) then

        -- document_condition without checks passes ALL documents, therefore `ok` stays true

        -- check if approved (null value means we don't care)
        if document_condition.approved is not null then
            ok = (ok AND (
                select document_condition.approved = coalesce(
                    case when public.is_client_company_feature_active(document.client_company_id, 'APPROVED_WITHOUT_VERIFIERS')
                    then public.is_document_approved_without_verifiers(document.id)
                    else public.is_document_approved(document.id)
                    end,
                    false -- is_document_approved -> null when there are no request releases, that is why we coalesce to false
                )
            ));
        end if;

        -- check if related partner company has a controller user
        if document_condition.has_controller_user_on_document_partner_company is not null then
            ok = (ok AND (
                select document_condition.has_controller_user_on_document_partner_company = exists (
                    select from public.partner_company
                        left join public.invoice on invoice.document_id = document.id
                        left join public.other_document on other_document.document_id = document.id
                    where partner_company.id = coalesce(invoice.partner_company_id, other_document.partner_company_id)
                    and (
                        partner_company.user_id is not null
                        or partner_company.user_group_id is not null
                    )
                )
            ));
        end if;

        -- check if payment status matches
        if document_condition.payment_status is not null then
            ok = (ok and (
                case document_condition.payment_status
                when 'PAID' then public.document_payment_status(document) in (
                    'PAID_WITH_BANK',
                    'PAID_WITH_CREDITCARD',
                    'PAID_WITH_CASH',
                    'PAID_WITH_PAYPAL',
                    'PAID_WITH_STRIPE',
                    'PAID_WITH_TRANSFERWISE',
                    'PAID_WITH_DIRECT_DEBIT'
                )
                else document_condition.payment_status::text = public.document_payment_status(document)::text
                end
            ));
        end if;

    end if;

    -- check document import date conditions
    FOREACH condition IN ARRAY coalesce(document_import_date_conditions, '{}') LOOP

        ok = (ok AND (
            rule.comparison_operator_compare_timestamp(
                condition.import_date_comparison,
                document.import_date::timestamptz,
                condition.import_date::timestamptz
            )
        ));

    END LOOP;

    -- check document client-company-tag conditions
    foreach condition in array coalesce(document_client_company_tag_conditions, '{}') loop

        case
            -- doesnt have any client-company-tag
            when condition.client_company_tag_id_equality = 'EQUAL_TO' and condition.client_company_tag_id is null
            then ok = (ok AND (
                not exists(select from public.document_tag
                    where document_tag.document_id = document.id)
                and not exists(select from public.real_estate_object_client_company_tag
                    inner join public.document_real_estate_object on document_real_estate_object.object_instance_id = real_estate_object_client_company_tag.object_instance_id
                    where document_real_estate_object.document_id = document.id)
                )
            );
            -- has any client-company-tag
            when condition.client_company_tag_id_equality = 'NOT_EQUAL_TO' and condition.client_company_tag_id is null
            then ok = (ok AND (
                exists(select from public.document_tag
                    where document_tag.document_id = document.id)
                or exists(select from public.real_estate_object_client_company_tag
                    inner join public.document_real_estate_object on document_real_estate_object.object_instance_id = real_estate_object_client_company_tag.object_instance_id
                    where document_real_estate_object.document_id = document.id)
                )
            );
            -- has this specific client-company-tag
            when condition.client_company_tag_id_equality = 'EQUAL_TO' and condition.client_company_tag_id is not null
            then ok = (ok AND (
                exists(select from public.document_tag
                    where document_tag.document_id = document.id
                    and document_tag.client_company_tag_id = condition.client_company_tag_id)
                or exists(select from public.real_estate_object_client_company_tag
                    inner join public.document_real_estate_object on document_real_estate_object.object_instance_id = real_estate_object_client_company_tag.object_instance_id
                    where document_real_estate_object.document_id = document.id
                    and real_estate_object_client_company_tag.client_company_tag_id = condition.client_company_tag_id)
                )
            );
            -- doesnt have this specific client-company-tag, but has another one
            when condition.client_company_tag_id_equality = 'NOT_EQUAL_TO' and condition.client_company_tag_id is not null
            then ok = (ok AND (
                exists(select from public.document_tag
                    where document_tag.document_id = document.id
                    and document_tag.client_company_tag_id <> condition.client_company_tag_id)
                or exists(select from public.real_estate_object_client_company_tag
                    inner join public.document_real_estate_object on document_real_estate_object.object_instance_id = real_estate_object_client_company_tag.object_instance_id
                    where document_real_estate_object.document_id = document.id
                    and real_estate_object_client_company_tag.client_company_tag_id <> condition.client_company_tag_id)
                )
            );
            -- woah what?
            else raise exception 'Impossible case when checking document client-company-tag condition %', condition;
        end case;

    end loop;

    -- check document workflow step conditions
    FOREACH condition IN ARRAY coalesce(document_document_workflow_step_conditions, '{}') LOOP

        ok = (ok AND (
            rule.equality_operator_compare(
                condition.document_workflow_step_id_equality,
                document.workflow_step_id::text,
                condition.document_workflow_step_id::text
            )
        ));

    END LOOP;

    -- check document approval conditions
    foreach condition in array coalesce(document_approval_conditions, '{}') loop

        ok = (ok and exists (
            with recursive approval_chain as (
                select document_approval.*
                from public.document_approval
                    inner join public.document_approval_request on document_approval_request.id = document_approval.request_id
                where document_approval_request.document_id = document.id
                and (document_approval_request.approver_id = condition.approver_id
                    or document_approval_request.blank_approver_type = condition.blank_approver_type)

                union

                select document_approval.*
                from approval_chain, public.document_approval
                where approval_chain.next_request_id = document_approval.request_id
            )
            select from approval_chain
            where approval_chain.next_request_id is null
            and not approval_chain.canceled
        ));

    end loop;

    -- check document real-estate-object conditions
    foreach condition in array coalesce(document_real_estate_object_conditions, '{}') loop

        case
            -- doesnt have any real-estate-object
            when condition.document_real_estate_object_instance_id_equality = 'EQUAL_TO' and condition.document_real_estate_object_instance_id is null
            then ok = (ok AND (
                not exists(select from public.document_real_estate_object
                    where document_real_estate_object.document_id = document.id)));
            -- has any real-estate-object
            when condition.document_real_estate_object_instance_id_equality = 'NOT_EQUAL_TO' and condition.document_real_estate_object_instance_id is null
            then ok = (ok AND (
                exists(select from public.document_real_estate_object
                    where document_real_estate_object.document_id = document.id)));
            -- has this specific real-estate-object
            when condition.document_real_estate_object_instance_id_equality = 'EQUAL_TO' and condition.document_real_estate_object_instance_id is not null
            then ok = (ok AND (
                exists(select from public.document_real_estate_object
                    where document_real_estate_object.document_id = document.id
                    and document_real_estate_object.object_instance_id = condition.document_real_estate_object_instance_id)));
            -- doesnt have this specific real-estate-object, but has another one
            when condition.document_real_estate_object_instance_id_equality = 'NOT_EQUAL_TO' and condition.document_real_estate_object_instance_id is not null
            then ok = (ok AND (
                exists(select from public.document_real_estate_object
                    where document_real_estate_object.document_id = document.id
                    and document_real_estate_object.object_instance_id <> condition.document_real_estate_object_instance_id)));
            -- woah what?
            else raise exception 'Impossible case when checking document real-estate-object condition %', condition;
        end case;

    end loop;

    return ok;
end
$$
language plpgsql stable;

comment on function rule.document_check is '@omit';
