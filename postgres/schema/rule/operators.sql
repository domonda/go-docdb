---- equality_operator ----

-- NOTE: only `EQUAL_TO` and `NOT_EQUAL_TO` allow comparisons between null values
--       all other equlity operators will result in an immediate `false` return

CREATE TYPE rule.equality_operator AS ENUM (
    'EQUAL_TO',    -- =
    'NOT_EQUAL_TO' -- !=
);
COMMENT ON TYPE rule.equality_operator IS 'Equality operators used for rule-based logic.';

CREATE FUNCTION rule.equality_operator_compare(
    operator rule.equality_operator,
    val1     text,
    val2     text
) RETURNS bool AS
$$
    SELECT
        CASE (operator)
            WHEN 'EQUAL_TO' THEN (val1 IS NOT DISTINCT FROM val2)
            WHEN 'NOT_EQUAL_TO' THEN (val1 IS DISTINCT FROM val2)
            ELSE false
        END
$$
LANGUAGE SQL IMMUTABLE;

COMMENT ON FUNCTION rule.equality_operator_compare IS '@omit';

---- comparison_operator ----

CREATE TYPE rule.comparison_operator AS ENUM (
    'EQUAL_TO',                 -- =
    'NOT_EQUAL_TO',             -- !=
    'GREATER_THEN',             -- >
    'GREATER_THEN_OR_EQUAL_TO', -- >=
    'LESS_THEN',                -- <
    'LESS_THEN_OR_EQUAL_TO'     -- <=
);
COMMENT ON TYPE rule.comparison_operator IS 'Comparison operators used for rule-based logic.';

CREATE FUNCTION rule.comparison_operator_compare_numeric(
    operator rule.comparison_operator,
    val1     numeric,
    val2     numeric -- put the action value here
) RETURNS bool AS
$$
    SELECT
        CASE (operator)
            WHEN 'EQUAL_TO' THEN (val1 IS NOT DISTINCT FROM val2)
            WHEN 'NOT_EQUAL_TO' THEN (val1 IS DISTINCT FROM val2)
            WHEN 'GREATER_THEN' THEN COALESCE(val1 > val2, false)
            WHEN 'GREATER_THEN_OR_EQUAL_TO' THEN COALESCE(val1 >= val2, false)
            WHEN 'LESS_THEN' THEN COALESCE(val1 < val2, false)
            WHEN 'LESS_THEN_OR_EQUAL_TO' THEN COALESCE(val1 <= val2, false)
            ELSE false
        END
$$
LANGUAGE SQL IMMUTABLE;

COMMENT ON FUNCTION rule.comparison_operator_compare_numeric IS '@omit';

----

CREATE FUNCTION rule.comparison_operator_compare_timestamp(
    operator rule.comparison_operator,
    val1     timestamptz,
    val2     timestamptz -- put the action value here
) RETURNS bool AS
$$
    SELECT
        CASE (operator)
            WHEN 'EQUAL_TO' THEN (val1 IS NOT DISTINCT FROM val2)
            WHEN 'NOT_EQUAL_TO' THEN (val1 IS DISTINCT FROM val2)
            WHEN 'GREATER_THEN' THEN COALESCE(val1 > val2, false)
            WHEN 'GREATER_THEN_OR_EQUAL_TO' THEN COALESCE(val1 >= val2, false)
            WHEN 'LESS_THEN' THEN COALESCE(val1 < val2, false)
            WHEN 'LESS_THEN_OR_EQUAL_TO' THEN COALESCE(val1 <= val2, false)
            ELSE false
        END
$$
LANGUAGE SQL IMMUTABLE;

COMMENT ON FUNCTION rule.comparison_operator_compare_timestamp IS '@omit';
