-- can return:
    -- null: no invoice checks are present
    -- true: invoice check passed, perform reaction
    -- false: invoice check hasent passed, no reaction
CREATE FUNCTION rule.invoice_check(
    action  rule.action,
    invoice public.invoice
) RETURNS boolean AS
$$
DECLARE
    -- initially the OK value is true because we AND the conditions
    ok boolean := true;
    -- conditionals
    invoice_conditions                    rule.invoice_condition[];
    invoice_completeness_level_conditions rule.invoice_completeness_level_condition[];
    invoice_partner_company_conditions    rule.invoice_partner_company_condition[];
    invoice_total_conditions              rule.invoice_total_condition[];
    invoice_invoice_date_conditions       rule.invoice_invoice_date_condition[];
    invoice_cost_center_conditions        rule.invoice_cost_center_condition[];
    invoice_cost_unit_conditions          rule.invoice_cost_unit_condition[];
    condition                             record;
    condition_result                      boolean := false;
BEGIN
    -- find invoice conditions
    SELECT
        array_agg(c) INTO invoice_conditions
    FROM rule.invoice_condition AS c
    WHERE (c.action_id = action.id);

    -- find invoice invoice completeness level condition
    SELECT
        array_agg(c) INTO invoice_completeness_level_conditions
    FROM rule.invoice_completeness_level_condition AS c
    WHERE (c.action_id = action.id);

    -- find invoice partner company conditions
    SELECT
        array_agg(c) INTO invoice_partner_company_conditions
    FROM rule.invoice_partner_company_condition AS c
    WHERE (c.action_id = action.id);

    -- find invoice total conditions
    SELECT
        array_agg(c) INTO invoice_total_conditions
    FROM rule.invoice_total_condition AS c
    WHERE (c.action_id = action.id);

    -- find invoice invoice date conditions
    SELECT
        array_agg(c) INTO invoice_invoice_date_conditions
    FROM rule.invoice_invoice_date_condition AS c
    WHERE (c.action_id = action.id);

    -- find invoice cost-center conditions
    SELECT
        array_agg(c) INTO invoice_cost_center_conditions
    FROM rule.invoice_cost_center_condition AS c
    WHERE (c.action_id = action.id);

    -- find invoice cost-unit conditions
    SELECT
        array_agg(c) INTO invoice_cost_unit_conditions
    FROM rule.invoice_cost_unit_condition AS c
    WHERE (c.action_id = action.id);

    -- if there are no conditions, return null
    IF (
        coalesce(array_length(invoice_conditions, 1), 0) = 0
    ) AND (
        invoice_completeness_level_conditions IS NULL
    ) AND (
        coalesce(array_length(invoice_partner_company_conditions, 1), 0) = 0
    ) AND (
        coalesce(array_length(invoice_total_conditions, 1), 0) = 0
    ) AND (
        coalesce(array_length(invoice_invoice_date_conditions, 1), 0) = 0
    ) AND (
        coalesce(array_length(invoice_cost_center_conditions, 1), 0) = 0
    ) AND (
        coalesce(array_length(invoice_cost_unit_conditions, 1), 0) = 0
    ) THEN
        RETURN null;

    END IF;

    -- if invoice does not exist, conditions cannot pass
    IF invoice IS NULL
    THEN
        RETURN false;
    END IF;

    -- check invoice conditions
    FOREACH condition IN ARRAY coalesce(invoice_conditions, '{}') LOOP

        ok = (ok AND true);

    END LOOP;

    -- check invoice invoice completeness level condition
    FOREACH condition IN ARRAY coalesce(invoice_completeness_level_conditions, '{}') LOOP

        ok = (ok AND (
            rule.equality_operator_compare(
                condition.completeness_level_equality,
                public.invoice_has_completeness_level(invoice, condition.completeness_level::public.invoice_completeness_level)::text,
                'true'
            )
        ));

    END LOOP;

    -- check invoice partner company conditions
    FOREACH condition IN ARRAY coalesce(invoice_partner_company_conditions, '{}') LOOP

        ok = (ok AND (
            rule.equality_operator_compare(
                condition.partner_company_id_equality,
                invoice.partner_company_id::text,
                condition.partner_company_id::text
            )
        ));

    END LOOP;

    -- check invoice total conditions
    FOREACH condition IN ARRAY coalesce(invoice_total_conditions, '{}') LOOP

        ok = (ok AND (
            rule.comparison_operator_compare_numeric(
                condition.total_comparison,
                ABS(invoice.total)::numeric,
                ABS(condition.total)::numeric
            )
        ));

    END LOOP;

    -- check invoice invoice date conditions
    FOREACH condition IN ARRAY coalesce(invoice_invoice_date_conditions, '{}') LOOP

        ok = (ok AND (
            rule.comparison_operator_compare_timestamp(
                condition.invoice_date_comparison,
                invoice.invoice_date::timestamptz,
                condition.invoice_date::timestamptz
            )
        ));

    END LOOP;

    -- check invoice cost-center conditions
    FOREACH condition IN ARRAY coalesce(invoice_cost_center_conditions, '{}') LOOP

        case
            -- doesnt have any cost-center
            when condition.client_company_cost_center_id_equality = 'EQUAL_TO' and condition.client_company_cost_center_id is null
            then ok = (ok AND (
                not exists(select from public.invoice_cost_center
                    where invoice_cost_center.document_id = invoice.document_id)));
            -- has any cost-center
            when condition.client_company_cost_center_id_equality = 'NOT_EQUAL_TO' and condition.client_company_cost_center_id is null
            then ok = (ok AND (
                exists(select from public.invoice_cost_center
                    where invoice_cost_center.document_id = invoice.document_id)));
            -- has this specific cost-center
            when condition.client_company_cost_center_id_equality = 'EQUAL_TO' and condition.client_company_cost_center_id is not null
            then ok = (ok AND (
                exists(select from public.invoice_cost_center
                    where invoice_cost_center.document_id = invoice.document_id
                    and invoice_cost_center.client_company_cost_center_id = condition.client_company_cost_center_id)));
            -- doesnt have this specific cost-center, but has another one
            when condition.client_company_cost_center_id_equality = 'NOT_EQUAL_TO' and condition.client_company_cost_center_id is not null
            then ok = (ok AND (
                exists(select from public.invoice_cost_center
                    where invoice_cost_center.document_id = invoice.document_id
                    and invoice_cost_center.client_company_cost_center_id <> condition.client_company_cost_center_id)));
            -- woah what?
            else raise exception 'Impossible case when checking invoice cost-center condition %', condition;
        end case;

    END LOOP;

    -- check invoice cost-unit conditions
    FOREACH condition IN ARRAY coalesce(invoice_cost_unit_conditions, '{}') LOOP

        case
            -- doesnt have any cost-unit
            when condition.client_company_cost_unit_id_equality = 'EQUAL_TO' and condition.client_company_cost_unit_id is null
            then ok = (ok AND (
                not exists(select from public.invoice_cost_unit
                    where invoice_cost_unit.invoice_document_id = invoice.document_id)));
            -- has any cost-unit
            when condition.client_company_cost_unit_id_equality = 'NOT_EQUAL_TO' and condition.client_company_cost_unit_id is null
            then ok = (ok AND (
                exists(select from public.invoice_cost_unit
                    where invoice_cost_unit.invoice_document_id = invoice.document_id)));
            -- has this specific cost-unit
            when condition.client_company_cost_unit_id_equality = 'EQUAL_TO' and condition.client_company_cost_unit_id is not null
            then ok = (ok AND (
                exists(select from public.invoice_cost_unit
                    where invoice_cost_unit.invoice_document_id = invoice.document_id
                    and invoice_cost_unit.client_company_cost_unit_id = condition.client_company_cost_unit_id)));
            -- doesnt have this specific cost-unit, but has another one
            when condition.client_company_cost_unit_id_equality = 'NOT_EQUAL_TO' and condition.client_company_cost_unit_id is not null
            then ok = (ok AND (
                exists(select from public.invoice_cost_unit
                    where invoice_cost_unit.invoice_document_id = invoice.document_id
                    and invoice_cost_unit.client_company_cost_unit_id <> condition.client_company_cost_unit_id)));
            -- woah what?
            else raise exception 'Impossible case when checking invoice cost-unit condition %', condition;
        end case;

    END LOOP;

    RETURN ok;
END
$$
LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION rule.invoice_check IS '@omit';
