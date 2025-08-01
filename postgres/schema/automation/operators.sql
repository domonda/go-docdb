-- NOTE: only `EQUAL_TO` and `NOT_EQUAL_TO` allow comparisons between null values
--       all other equlity operators will result in an immediate `false` return

create type automation.equality_operator as enum (
  'EQUAL_TO',    -- =
  'NOT_EQUAL_TO' -- !=
);

create function automation.equality_operator_compare(
    operator   automation.equality_operator,
    filter_val text,
    val        text
) returns bool as $$
  select case operator
    when 'EQUAL_TO' then (val is not distinct from filter_val)
    when 'NOT_EQUAL_TO' then (val is distinct from filter_val)
    else false
  end
$$ language sql immutable;
comment on function automation.equality_operator_compare is '@omit';

----

create type automation.comparison_operator as enum (
  'EQUAL_TO',                 -- =
  'NOT_EQUAL_TO',             -- !=
  'GREATER_THAN',             -- >
  'GREATER_THAN_OR_EQUAL_TO', -- >=
  'LESS_THAN',                -- <
  'LESS_THAN_OR_EQUAL_TO'     -- <=
);

create function automation.comparison_operator_compare_numeric(
    operator   automation.comparison_operator,
    filter_val numeric,
    val        numeric
) returns bool as $$
  select case operator
    when 'EQUAL_TO' then (val is not distinct from filter_val)
    when 'NOT_EQUAL_TO' then (val is distinct from filter_val)
    when 'GREATER_THAN' then coalesce(val > filter_val, false)
    when 'GREATER_THAN_OR_EQUAL_TO' then coalesce(val >= filter_val, false)
    when 'LESS_THAN' then coalesce(val < filter_val, false)
    when 'LESS_THAN_OR_EQUAL_TO' then coalesce(val <= filter_val, false)
    else false
  end
$$ language sql immutable;
comment on function automation.comparison_operator_compare_numeric is '@omit';

create function automation.comparison_operator_compare_timestamp(
    operator   automation.comparison_operator,
    filter_val timestamptz,
    val        timestamptz
) returns bool as
$$
  select case operator
    when 'EQUAL_TO' then (val is not distinct from filter_val)
    when 'NOT_EQUAL_TO' then (val is distinct from filter_val)
    when 'GREATER_THAN' then coalesce(val > filter_val, false)
    when 'GREATER_THAN_OR_EQUAL_TO' then coalesce(val >= filter_val, false)
    when 'LESS_THAN' then coalesce(val < filter_val, false)
    when 'LESS_THAN_OR_EQUAL_TO' then coalesce(val <= filter_val, false)
    else false
  end
$$ language sql immutable;
comment on function automation.comparison_operator_compare_timestamp is '@omit';
