-- Must have all words: one two three
-- Must have all words in given order: "one two three"
-- Has any of the words: one | two | three
-- Has word that begins with: Österr*
-- Has one word, but not the other: one -other
-- (To be compatible instead of space to search for all words with: one & two + three)
CREATE FUNCTION public.domonda_query(search_str text) RETURNS text AS
$$
DECLARE
    quotes text[];
    quote text;
    fixed_quote text;
BEGIN
    -- RAISE WARNING 'domonda_query(%)', search_str;

    -- Replace quoted string with <->
    search_str = replace(search_str, '"', '''');

    LOOP
        quotes = regexp_matches(search_str, '''.+?''');
        IF quotes IS NULL THEN
            EXIT;
        END IF;
        quote = quotes[1];
        fixed_quote = regexp_replace(quote, '\s+', '<->', 'g');
        fixed_quote = regexp_replace(fixed_quote, '^''\s*', '(');
        fixed_quote = regexp_replace(fixed_quote, '\s*''$', ')');

        search_str = replace(search_str, quote, fixed_quote);
    END LOOP;

    -- Remove spaces around operators and replace aliases
    search_str = regexp_replace(search_str, '\s*&\s*', '&', 'g');
    search_str = regexp_replace(search_str, '\s*\+\s*', '&', 'g');
    search_str = regexp_replace(search_str, '\s*\|\s*', '|', 'g');
    search_str = regexp_replace(search_str, '\s*\!\s*', '&!', 'g');
    search_str = regexp_replace(search_str, '^\-', '!');
    search_str = regexp_replace(search_str, '\s+\-\s*', '&!', 'g');
    search_str = regexp_replace(search_str, '([^<])(\-\s*)', '\1&!', 'g');

    -- Remaining spaces are & operators
    search_str = regexp_replace(search_str, '\s+', '&', 'g');

    search_str = replace(search_str, '*', ':*');

    -- Put spaces around operands to make search_str more readable
    search_str = replace(search_str, '&', ' & ');
    search_str = replace(search_str, '|', ' | ');
    search_str = replace(search_str, '<->', ' <-> ');

    -- RAISE WARNING 'domonda_query: %', search_str;
    RETURN search_str;
END;
$$
LANGUAGE plpgsql STRICT IMMUTABLE;

----

CREATE FUNCTION public.format_money_int(amout float8) RETURNS text AS
$$
BEGIN
    RETURN coalesce(trim(to_char(amout, '999999999999')), '');
END;
$$
LANGUAGE plpgsql STRICT IMMUTABLE;

----

CREATE FUNCTION public.format_money_german(amout float8) RETURNS text AS
$$
BEGIN
    RETURN coalesce(replace(trim(to_char(amout, '999999999999.99')), '.', ','));
END;
$$
LANGUAGE plpgsql STRICT IMMUTABLE;

----

CREATE FUNCTION public.format_money_english(amout float8) RETURNS text AS
$$
BEGIN
    RETURN coalesce(trim(to_char(amout, '999999999999.99')));
END;
$$
LANGUAGE plpgsql STRICT IMMUTABLE;

----

CREATE FUNCTION public.filename_from_path(path text) RETURNS text AS
$$
BEGIN
    RETURN regexp_replace(path, '^.+[/\\]', '');
END;
$$
LANGUAGE plpgsql STRICT IMMUTABLE;

----

-- TODO: this should be `public.from_german_number_to_numeric`

CREATE FUNCTION public.to_numeric(text) RETURNS numeric AS
$$
DECLARE n numeric;
BEGIN
    n = CAST(replace($1, ',', '.') AS numeric);
    RETURN n;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$
LANGUAGE plpgsql IMMUTABLE;

----

CREATE FUNCTION public.work_days_since(since_date date, until_date date) RETURNS bigint AS
$$
    SELECT count(*) FROM generate_series(1, (until_date - since_date)) AS i
        WHERE date_part('dow', since_date + i) NOT IN (0,6);
$$
LANGUAGE SQL STABLE;

----

CREATE FUNCTION public.work_days_since(since_date date) RETURNS bigint AS
$$
    SELECT public.work_days_since(since_date, now()::date);
$$
LANGUAGE SQL STABLE;

----

CREATE FUNCTION public.is_valid_uuid(str text) RETURNS bool AS
$$
    BEGIN
        RETURN (str IS NOT NULL) AND (CAST(str AS uuid) <> '00000000-0000-0000-0000-000000000000');
    EXCEPTION WHEN invalid_text_representation THEN
        RETURN false;
    END;
$$
LANGUAGE plpgsql IMMUTABLE;

----

CREATE FUNCTION public.is_valid_timestamp(str text) RETURNS bool AS
$$
    BEGIN
        RETURN (CAST(str AS timestamptz) IS NOT NULL);
    EXCEPTION WHEN data_exception THEN
        RETURN false;
    END;
$$
LANGUAGE plpgsql IMMUTABLE;

----

CREATE FUNCTION public.to_utc_rfc3339(t timestamptz) RETURNS text AS
$$
    SELECT to_char(t at time zone 'UTC', 'FXYYYY-MM-DD"T"HH:MI:SS.US"Z"')
$$
LANGUAGE SQL IMMUTABLE STRICT;

----

CREATE FUNCTION public.to_relay_node_id(tablename text, id uuid) RETURNS text AS
$$
    SELECT regexp_replace(encode(convert_to(replace(CAST(json_build_array(tablename, id) AS text), ' ', ''), 'UTF8'), 'base64'), '[\n\r]+', '', 'g');
$$
LANGUAGE SQL IMMUTABLE STRICT;

COMMENT ON FUNCTION public.to_relay_node_id IS 'Converts the passed id in the table to the Relay global node unique ID specification. Which is essentially a tablename+id tuple encoded in base64. The tablename must be plural.';

----

CREATE FUNCTION public.percent_difference_between_numbers(
    x float8,
    y float8
) RETURNS float8 AS
$$
    SELECT CASE
        WHEN (x = 0 AND y = 0) THEN 0
        WHEN ((x * -1) = y) THEN 2
        ELSE (x - y) / ((x + y) / 2)
    END
$$
LANGUAGE SQL IMMUTABLE STRICT;

COMMENT ON FUNCTION public.percent_difference_between_numbers IS 'Calculates the difference between the two numbers in percentages. If the percentage is negative, the first number is smaller then the second one, and also the other way arround.';

----

CREATE FUNCTION public.same_words_in_sentences(
    sentence1 text,
    sentence2 text
) RETURNS bool AS
$$
    SELECT a1 = b1
        FROM (
            SELECT string_agg(word, ' ') AS a1 FROM (
                SELECT word FROM unnest(string_to_array(trim(sentence1), ' ')) AS word
                ORDER BY word
            ) AS a1
        ) AS a2, (
            SELECT string_agg(word, ' ') AS b1 FROM (
                SELECT word FROM unnest(string_to_array(trim(sentence2), ' ')) AS word
                ORDER BY word
            ) AS b1
        ) AS b2
   WHERE length(trim(sentence1)) = length(trim(sentence2))
   UNION ALL
   SELECT false
   LIMIT 1
$$
LANGUAGE SQL IMMUTABLE;

----

CREATE FUNCTION public.to_german_number(
    "number" numeric
) RETURNS text AS
$$
    SELECT replace(
        round(to_german_number."number", 2)::text, -- round to 2 decimal points
        '.', ',' -- replace decimal seperator
    )
$$
LANGUAGE SQL IMMUTABLE;

----

CREATE FUNCTION public.uuid_or_null(maybeUuid text)
RETURNS uuid AS
$$
BEGIN
    RETURN maybeUuid::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RETURN NULL;
END
$$
LANGUAGE plpgsql IMMUTABLE;

----

create function private.sanitize_document_fulltext(fulltext text) returns text as
$$
declare
  lines text[];
  line text;
  sanitizedLines text[];
  words text[];
  word text;
  sanitizedWords text[] := '{}';
begin
  lines := string_to_array(fulltext, E'\n');

  foreach line in array lines loop
    words := string_to_array(line, ' ');
    sanitizedWords := array[]::text[];

    foreach word in array words loop
      word := trim(word);

      if length(word) = 0 or length(word) > 128 then
        continue;
      end if;

      if word ~ '^\W*$' then
        continue;
      end if;

      sanitizedWords := array_append(sanitizedWords, word);
    end loop;

    if array_length(sanitizedWords, 1) is null then
      continue;
    end if;

    sanitizedLines := array_append(sanitizedLines, array_to_string(sanitizedWords, ' '));
  end loop;

  return array_to_string(sanitizedLines, E'\n');
end
$$ language plpgsql immutable strict;

-- just a convenience wrapper for easier current settings flags checks (no nulls returned ever)
create function private.current_setting_flag(name text)
returns boolean as $$
    select coalesce(nullif(current_setting(name, true), '')::boolean, false)
$$ language sql stable;
comment on function private.current_setting_flag is '@notNull';

-- converts text to a number by extracting only digits from the text and then casting them to a number
create function private.text_to_bigint(val text)
returns bigint as $$
    select nullif(regexp_replace(val, '\D','','g'), '')::bigint
$$ language sql immutable strict;
