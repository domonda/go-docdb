CREATE FUNCTION matching.perform_checks(
    -- check
    client_company_id uuid,
    -- invoice
    invoice_total         float8,
    invoice_number        text,
    invoice_order_number  text,
    invoice_date          date,
    invoice_partner_names text[],
    invoice_partner_iban  public.bank_iban,
    -- transaction
    transaction_type         matching.transaction_type,
    transaction_total        float8,
    transaction_purpose      text,
    transaction_date         date,
    transaction_partner_name text,
    transaction_partner_iban public.bank_iban
) RETURNS uuid AS
$$
DECLARE
    -- validation --
        -- dates_diff_in_days holds the difference between the invoice date and the transaction date in days
    dates_diff_in_days int := DATE_PART('day', transaction_date::timestamptz - invoice_date::timestamptz);
    -- sanitize texts --
        -- invoice or order number
    replace_in_invoice_and_order_number json := $json$[
        {"\\": ""},
        {"/": ""},
        {"-": ""},
        {":": ""},
        {".": ""},
        {"\n": " "}
    ]$json$;
    sanitized_invoice_number       text;
    sanitized_invoice_order_number text;
        -- transaction purpose
    replace_in_transaction_purpose json := $json$[
        {"\\": ""},
        {"/": ""},
        {"-": ""},
        {":": ""},
        {".": ""},
        {"basislastschrift": ""},
        {"auftraggeber": ""},
        {"\n": " "}
    ]$json$;
    sanitized_transaction_purpose text;
        -- partner_name
    -- NOTE: keys are regular expressions
    replace_in_transaction_partner_name json := $json$[
        {"\\s*<(.+\\@.+\\.[A-z]+)*>": ""},
        {"\\.eur": ""},
        {"\\.org": ""},
        {"\\.com": ""},
        {"\\.at": ""},
        {"\\.de": ""},
        {"\\.us": ""},
        {"www\\.": ""},
        {"basislastschrift": ""},
        {"auftraggeber": ""},
        {"\\n": " "}
    ]$json$;
    transaction_partner_name_or_partner              text;
    transaction_partner_name_or_partner_from_purpose text;
    i_invoice_partner_name                           text;
    partner_names_appear                             boolean := false;
    partner_names_similarity                         real := 0;
        -- replace item
    replace_text RECORD; -- (key,value)
    -- amounts
    rounded_invoice_total     numeric;
    rounded_transaction_total numeric;
    totals_diff               numeric;
    totals_perc_diff          float8;
    -- perform --
    some_checked       boolean;
    matching_check_ids uuid[];
    matching_check_id  uuid;
    matching_check     RECORD; -- can be any check
BEGIN

    -- validate entries, if this validation fails, a match could not possibly exist!
    IF (
        -- transaction total must exist not be 0
        COALESCE(transaction_total, 0) = 0
    ) OR (
        -- transaction purpose must exist
        COALESCE(TRIM(transaction_purpose), '') = ''
    ) OR (
        -- transaction date must exist
        transaction_date IS NULL
    ) OR (
        -- invoice date must exist
        invoice_date IS NULL
    ) OR (
        -- invoice date must not be more then 28 days (4 weeks) appart from the transaction date in the future
        dates_diff_in_days <= -28
    ) OR (
        -- invoice date and transaction date must not be more then 120 days (4 months) appart in the past
        dates_diff_in_days >= 120
    ) THEN

        -- insufficient valid arguments to proceed with matching
        RETURN NULL;

    END IF;

    -- find checks related to the client ordered by the priority
    SELECT
        array_agg("check".id) INTO matching_check_ids
    FROM (
        SELECT
            c.id
        FROM matching."check" AS c
            INNER JOIN (
                matching.client_company_rule_check AS ccrc
                INNER JOIN matching.client_company_rule AS ccr ON (ccr.id = ccrc.rule_id)
            ) ON (ccrc.check_id = c.id)
        WHERE (
            perform_checks.client_company_id IS NULL
            OR (c.id NOT IN (SELECT unnest(skip_matching_check_ids) FROM public.client_company WHERE client_company.company_id = perform_checks.client_company_id))
        ) AND (
            ccrc.enabled
        ) AND (
            CASE (EXISTS (SELECT 1 FROM matching.client_company_rule WHERE client_company_rule.client_company_id = perform_checks.client_company_id))
                WHEN true THEN ccr.client_company_id = perform_checks.client_company_id
                ELSE ccr.client_company_id IS NULL
            END
        )
        ORDER BY ccrc.priority DESC
    ) AS "check";

    -- if there are no checks, return null
    IF (COALESCE(array_length(matching_check_ids, 1), 0) = 0) THEN

        RETURN null;

    END IF;

    -- check sub-checks
    <<matching_check_ids_loop>>
    FOREACH matching_check_id IN ARRAY COALESCE(matching_check_ids, '{}') LOOP

        -- if you created a check without sub-checks, everything would match!
        -- thats what this flag prevents. at least one sub-check has to be checked
        -- for a valid match.
        some_checked := false;

        -- check transaction type
        FOR matching_check IN (
            SELECT * FROM matching.check_transaction_type WHERE check_id = matching_check_id
        ) LOOP

            some_checked := true;

            -- if the check is failing, continue to other checks
            CONTINUE matching_check_ids_loop WHEN NOT (
                matching_check.transaction_type = perform_checks.transaction_type
            );

        END LOOP;

        -- check totals
        FOR matching_check IN (
            SELECT * FROM matching.check_totals WHERE check_id = matching_check_id
        ) LOOP

            some_checked := true;

            -- round invoice total to 2 decimal places
            rounded_invoice_total := round(invoice_total::numeric, 2);
            -- round transaction total to 2 decimal places
            rounded_transaction_total := round(transaction_total::numeric, 2);
            -- absolute difference between the totals
            totals_diff := ABS(rounded_invoice_total - rounded_transaction_total);
            -- totals_perc_diff calculates the difference between the totals
                -- case difference is positive or zero: rounded_transaction_total >= rounded_invoice_total
                -- case difference is negative:         rounded_transaction_total < rounded_invoice_total
            totals_perc_diff := public.percent_difference_between_numbers(rounded_transaction_total, rounded_invoice_total);

            -- if the check is failing, continue to other checks
            CONTINUE matching_check_ids_loop WHEN NOT (
                (
                    totals_diff <= matching_check.max_diff
                ) AND (
                    matching_check.diff_in_perc_from <= totals_perc_diff
                ) AND (
                    totals_perc_diff <= matching_check.diff_in_perc_to
                )
            );

        END LOOP;

        -- check IBANs
        FOR matching_check IN (
            SELECT * FROM matching.check_ibans WHERE check_id = matching_check_id
        ) LOOP

            some_checked := true;

            -- if the check is failing, continue to other checks
            CONTINUE matching_check_ids_loop WHEN NOT (
                (
                    perform_checks.invoice_partner_iban IS NOT NULL
                ) AND (
                    perform_checks.transaction_partner_iban IS NOT NULL
                ) AND (
                    perform_checks.invoice_partner_iban = perform_checks.transaction_partner_iban
                )
            );

        END LOOP;

        -- sanitize transaction purpose if necessary
        IF EXISTS (SELECT FROM matching.check_invoice_or_order_number_in_purpose WHERE check_id = matching_check_id)
        OR EXISTS (SELECT FROM matching.check_partner_names_similarity WHERE check_id = matching_check_id)
        THEN

            -- sanitize transaction purpose
            sanitized_transaction_purpose := lower(transaction_purpose);
            FOR replace_text IN (
                SELECT replace.* FROM
                    json_array_elements(replace_in_transaction_purpose),
                    json_each_text(value) AS replace
            ) LOOP
                sanitized_transaction_purpose = replace(
                    sanitized_transaction_purpose,
                    replace_text."key",
                    replace_text."value"
                );
            END LOOP;

            -- remove spaces from transaction purpose
            sanitized_transaction_purpose = replace(sanitized_transaction_purpose, ' ', '');

            -- sanitize and extract partner_name from purpose
            transaction_partner_name_or_partner_from_purpose = split_part(trim(transaction_purpose), ' ', 1); -- extract partner from purpose
            FOR replace_text IN (
                SELECT replace.* FROM
                    json_array_elements(replace_in_transaction_purpose),
                    json_each_text(value) AS replace
                WHERE "key" <> '.' -- we skip removing dots because we want the partner_name domains (partner.com/.at/.de)
            ) LOOP
                transaction_partner_name_or_partner_from_purpose = replace(
                    transaction_partner_name_or_partner_from_purpose,
                    replace_text."key",
                    replace_text."value"
                );
            END LOOP;
        END IF;

        -- check invoice or order number in purpose
        FOR matching_check IN (
            SELECT * FROM matching.check_invoice_or_order_number_in_purpose WHERE check_id = matching_check_id
        ) LOOP

            some_checked := true;

            -- sanitize invoice and order number
            sanitized_invoice_number := lower(invoice_number);
            sanitized_invoice_order_number := lower(invoice_order_number);
            FOR replace_text IN (
                SELECT replace.* FROM
                    json_array_elements(replace_in_invoice_and_order_number),
                    json_each_text(value) AS replace
            ) LOOP
                sanitized_invoice_number = replace(
                    sanitized_invoice_number,
                    replace_text."key",
                    replace_text."value"
                );
                sanitized_invoice_order_number = replace(
                    sanitized_invoice_order_number,
                    replace_text."key",
                    replace_text."value"
                );
            END LOOP;
            sanitized_invoice_number = replace(sanitized_invoice_number, ' ', ''); -- remove spaces
            sanitized_invoice_order_number = replace(sanitized_invoice_order_number, ' ', ''); -- remove spaces

            -- if the `take_last_chars` is specified, overwrite the invoice and order number
            IF COALESCE(matching_check.take_last_chars, 0) > 0 THEN

                sanitized_invoice_number := RIGHT(sanitized_invoice_number, matching_check.take_last_chars);
                sanitized_invoice_order_number := RIGHT(sanitized_invoice_order_number, matching_check.take_last_chars);

            END IF;

            -- if the check is failing, continue to other checks
            CONTINUE matching_check_ids_loop WHEN NOT (
                (
                    -- invoice number
                    (
                        COALESCE(LENGTH(sanitized_invoice_number), 0) >= matching_check.min_len
                    ) AND (
                        sanitized_transaction_purpose LIKE '%' || sanitized_invoice_number || '%'
                    )
                ) OR (
                    -- invoice order number
                    (
                        COALESCE(LENGTH(sanitized_invoice_order_number), 0) >= matching_check.min_len
                    ) AND (
                        sanitized_transaction_purpose LIKE '%' || sanitized_invoice_order_number || '%'
                    )
                )
            );

        END LOOP;

        -- check dates
        FOR matching_check IN (
            SELECT * FROM matching.check_dates WHERE check_id = matching_check_id
        ) LOOP

            some_checked := true;

            -- if the check is failing, continue to other checks
            CONTINUE matching_check_ids_loop WHEN NOT (
                (
                    matching_check.diff_in_days_from <= dates_diff_in_days
                ) AND (
                    dates_diff_in_days <= matching_check.diff_in_days_to
                )
            );

        END LOOP;

        -- check invoice date in purpose
        FOR matching_check IN (
            SELECT * FROM matching.check_invoice_date_in_purpose WHERE check_id = matching_check_id
        ) LOOP

            some_checked := true;

            -- if the check is failing, continue to other checks
            CONTINUE matching_check_ids_loop WHEN NOT (
                transaction_purpose LIKE '%' || to_char(invoice_date, matching_check.format) || '%'
            );

        END LOOP;

        -- check partner name similarity
        FOR matching_check IN (
            SELECT * FROM matching.check_partner_names_similarity WHERE check_id = matching_check_id
        ) LOOP

            some_checked := true;

            -- transaction partner or maybe the partner derived from the transaction purpose
                -- try taking the actual transaction partner
            transaction_partner_name_or_partner := lower(nullif(trim(transaction_partner_name), ''));
                -- otherwise take the partner from the transaction purpose
            IF transaction_partner_name_or_partner IS NULL THEN
                transaction_partner_name_or_partner = transaction_partner_name_or_partner_from_purpose;
            END IF;
            FOR replace_text IN (
                SELECT replace.* FROM
                    json_array_elements(replace_in_transaction_partner_name),
                    json_each_text(value) AS replace
            ) LOOP
                transaction_partner_name_or_partner = regexp_replace(
                    transaction_partner_name_or_partner,
                    replace_text."key",
                    replace_text."value"
                );
            END LOOP;

            foreach i_invoice_partner_name in array coalesce(invoice_partner_names, '{}') loop
                -- does the transaction partner appear in any of the invoice partners
                if not partner_names_appear then
                    partner_names_appear := replace(coalesce(i_invoice_partner_name, ''), ' ', '') ILIKE '%' || replace(coalesce(transaction_partner_name_or_partner, ''), ' ', '') || '%';
                end if;

                -- how similar are the partner names. take the higher similarity comparing both ways for each invoice partner
                partner_names_similarity := greatest(
                    word_similarity(coalesce(transaction_partner_name_or_partner, ''), coalesce(i_invoice_partner_name, '')),
                    word_similarity(coalesce(i_invoice_partner_name, ''), coalesce(transaction_partner_name_or_partner, '')),
                    partner_names_similarity
                );
            end loop;

            -- if the check is failing, continue to other checks
            CONTINUE matching_check_ids_loop WHEN NOT (
                (
                    LENGTH(COALESCE(transaction_partner_name_or_partner, '')) >= matching_check.min_len
                ) AND (
                    (partner_names_appear) OR (partner_names_similarity >= matching_check.similarity)
                )
            );

        END LOOP;

        -- if some checks were performed and the loop was not continued, its a match!
        IF some_checked THEN

            RETURN matching_check_id;

        END IF;

    END LOOP;

    RETURN null;

END;
$$
LANGUAGE plpgsql STABLE
COST 10000;

COMMENT ON FUNCTION matching.perform_checks IS '@omit';
