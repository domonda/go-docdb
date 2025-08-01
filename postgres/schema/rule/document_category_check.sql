-- can return:
    -- null: no document_category checks are present
    -- true: document_category check passed, perform reaction
    -- false: document_category check hasent passed, no reaction
CREATE FUNCTION rule.document_category_check(
    action            rule.action,
    document_category public.document_category
) RETURNS boolean AS
$$
DECLARE
    -- initially the OK value is true because we AND the conditions
    ok boolean := true;
    -- conditionals
    document_category_id_conditions            rule.document_category_id_condition[];
    document_category_document_type_conditions rule.document_category_document_type_condition[];
    condition                                  record;
    condition_result                           boolean := false;
BEGIN
    -- find document category id conditions
    SELECT
        array_agg(c) INTO document_category_id_conditions
    FROM rule.document_category_id_condition AS c
    WHERE (c.action_id = action.id);

    -- find document category document type conditions
    SELECT
        array_agg(c) INTO document_category_document_type_conditions
    FROM rule.document_category_document_type_condition AS c
    WHERE (c.action_id = action.id);

    -- if there are no conditions, return null
    IF (
        coalesce(array_length(document_category_id_conditions, 1), 0) = 0
    ) AND (
        coalesce(array_length(document_category_document_type_conditions, 1), 0) = 0
    ) THEN

        RETURN null;

    END IF;

    -- if document category does not exist, conditions cannot pass
    IF document_category IS NULL
    THEN
        RETURN false;
    END IF;

    -- check document category id conditions
    FOREACH condition IN ARRAY coalesce(document_category_id_conditions, '{}') LOOP

        ok = (ok AND (
            rule.equality_operator_compare(
                condition.document_category_id_equality,
                document_category.id::text,
                condition.document_category_id::text
            )
        ));

    END LOOP;

    -- check document category document type conditions
    FOREACH condition IN ARRAY coalesce(document_category_document_type_conditions, '{}') LOOP

        ok = (ok AND (
            rule.equality_operator_compare(
                condition.document_type_equality,
                document_category.document_type::text,
                condition.document_type::text
            )
        ));

    END LOOP;

    RETURN ok;
END
$$
LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION rule.document_category_check IS '@omit';
