-- pain.001
-- NOTE: pain.001 does not have any sub-checks its just a placeholder because the check is ran in a seperate custom query

-- dc878f75-3127-4c89-99eb-8f66b118a98f --

INSERT INTO matching.check (id, name)
    VALUES ('dc878f75-3127-4c89-99eb-8f66b118a98f', 'pain.001');

----

-- transaction type is bank
-- ibans match
-- totals match with allowed +-10% deviation (with max total diff of 300)
-- invoice or order number (min length of 3 chars) appears in transaction purpose

-- c2521919-d38b-44f2-a36b-acbb8eadbfb0 --

INSERT INTO matching.check (id, name)
    VALUES ('c2521919-d38b-44f2-a36b-acbb8eadbfb0', 'Default 1');

INSERT INTO matching.check_transaction_type (check_id, transaction_type)
    VALUES ('c2521919-d38b-44f2-a36b-acbb8eadbfb0', 'BANK');

INSERT INTO matching.check_ibans (check_id)
    VALUES ('c2521919-d38b-44f2-a36b-acbb8eadbfb0');

INSERT INTO matching.check_totals (check_id, max_diff, diff_in_perc_from, diff_in_perc_to)
    VALUES ('c2521919-d38b-44f2-a36b-acbb8eadbfb0', 300, -0.10, 0.10);

INSERT INTO matching.check_invoice_or_order_number_in_purpose (check_id, min_len)
    VALUES ('c2521919-d38b-44f2-a36b-acbb8eadbfb0', 3);
----

-- invoice or order number (min length of 4 chars) appears in transaction purpose
-- dates are not more then 120 days apart (invoice date must be in the past)
-- totals match with allowed +-10% deviation (with max total diff of 999,999 (no max total diff))

-- 691d54db-2ab1-4f47-a2d9-3a1760805e65 --

INSERT INTO matching.check (id, name, description)
    VALUES (
        '691d54db-2ab1-4f47-a2d9-3a1760805e65',
        'Invoice number and 120 days date diff check',
        'Checks if the invoice or order number appears in the purpose, has at least 4 characters and the date difference is not more than 120 days.'
    );

INSERT INTO matching.check_dates (check_id, diff_in_days_from, diff_in_days_to)
    VALUES ('691d54db-2ab1-4f47-a2d9-3a1760805e65', 0, 120);

INSERT INTO matching.check_invoice_or_order_number_in_purpose (check_id, min_len)
    VALUES ('691d54db-2ab1-4f47-a2d9-3a1760805e65', 4);

INSERT INTO matching.check_totals (check_id, max_diff, diff_in_perc_from, diff_in_perc_to)
    VALUES ('691d54db-2ab1-4f47-a2d9-3a1760805e65', 999999, -0.10, 0.10);

----

-- transaction type is bank
-- ibans match
-- totals match with allowed +-3% deviation (with max total diff of 100)
-- dates are not more then 18 days apart (invoice date must be in the past)

-- cdd473d4-a49d-433f-ad16-3f584f546c17 --

INSERT INTO matching.check (id, name)
    VALUES ('cdd473d4-a49d-433f-ad16-3f584f546c17', 'Default 2');

INSERT INTO matching.check_transaction_type (check_id, transaction_type)
    VALUES ('cdd473d4-a49d-433f-ad16-3f584f546c17', 'BANK');

INSERT INTO matching.check_ibans (check_id)
    VALUES ('cdd473d4-a49d-433f-ad16-3f584f546c17');

INSERT INTO matching.check_totals (check_id, max_diff, diff_in_perc_from, diff_in_perc_to)
    VALUES ('cdd473d4-a49d-433f-ad16-3f584f546c17', 100, -0.03, 0.03);

INSERT INTO matching.check_dates (check_id, diff_in_days_from, diff_in_days_to)
    VALUES ('cdd473d4-a49d-433f-ad16-3f584f546c17', 0, 18);

----

-- transaction type is bank
-- totals match exactly
-- dates are not more then 65 days apart (invoice date must be in the past)
-- transaction partner is at least 3 characters long and is at least 65% similar to the invoice partner

-- 5420b96a-b718-440b-91c4-2a9d8aa43d88 --

INSERT INTO matching.check (id, name)
    VALUES ('5420b96a-b718-440b-91c4-2a9d8aa43d88', 'Default 3');

INSERT INTO matching.check_transaction_type (check_id, transaction_type)
    VALUES ('5420b96a-b718-440b-91c4-2a9d8aa43d88', 'BANK');

INSERT INTO matching.check_totals (check_id, max_diff, diff_in_perc_from, diff_in_perc_to)
    VALUES ('5420b96a-b718-440b-91c4-2a9d8aa43d88', 0, 0, 0);

INSERT INTO matching.check_dates (check_id, diff_in_days_from, diff_in_days_to)
    VALUES ('5420b96a-b718-440b-91c4-2a9d8aa43d88', 0, 65);

INSERT INTO matching.check_partner_names_similarity (check_id, min_len, similarity)
    VALUES ('5420b96a-b718-440b-91c4-2a9d8aa43d88', 3, 0.65);

----

-- totals match exactly
-- invoice or order number (min length of 3 chars) appears in transaction purpose

-- bd2ddabf-88b6-4f69-ba55-1da4dcb5c1cc --

INSERT INTO matching.check (id, name)
    VALUES ('bd2ddabf-88b6-4f69-ba55-1da4dcb5c1cc', 'Default 4');

INSERT INTO matching.check_totals (check_id, max_diff, diff_in_perc_from, diff_in_perc_to)
    VALUES ('bd2ddabf-88b6-4f69-ba55-1da4dcb5c1cc', 0, 0, 0);

INSERT INTO matching.check_invoice_or_order_number_in_purpose (check_id, min_len)
    VALUES ('bd2ddabf-88b6-4f69-ba55-1da4dcb5c1cc', 3);

----

-- totals match with allowed 2% negative deviation and 10% positive deviation (with max total diff of 300)
-- invoice or order number (min length of 4 chars) appears in transaction purpose

-- 8e278729-13b3-410e-942c-179ebace724b --

INSERT INTO matching.check (id, name)
    VALUES ('8e278729-13b3-410e-942c-179ebace724b', 'Default 5');

INSERT INTO matching.check_totals (check_id, max_diff, diff_in_perc_from, diff_in_perc_to)
    VALUES ('8e278729-13b3-410e-942c-179ebace724b', 300, -0.02, 0.10);

INSERT INTO matching.check_invoice_or_order_number_in_purpose (check_id, min_len)
    VALUES ('8e278729-13b3-410e-942c-179ebace724b', 4);

----

-- totals match with allowed 2% negative deviation and 5% positive deviation (with max total diff of 300)
-- last 5 characters of invoice or order number appears in the transaction purpose
-- dates are not more than 28 days apart (invoice date can be up to 14 days in the future)

-- 04dc7837-0e82-43d1-8d2f-deaecedfd8ec --

INSERT INTO matching.check (id, name)
    VALUES ('04dc7837-0e82-43d1-8d2f-deaecedfd8ec', 'Default 6');

INSERT INTO matching.check_totals (check_id, max_diff, diff_in_perc_from, diff_in_perc_to)
    VALUES ('04dc7837-0e82-43d1-8d2f-deaecedfd8ec', 300, -0.02, 0.05);

INSERT INTO matching.check_invoice_or_order_number_in_purpose (check_id, min_len, take_last_chars)
    VALUES ('04dc7837-0e82-43d1-8d2f-deaecedfd8ec', 5, 5);

INSERT INTO matching.check_dates (check_id, diff_in_days_from, diff_in_days_to)
    VALUES ('04dc7837-0e82-43d1-8d2f-deaecedfd8ec', -14, 28);

----

-- transaction type is credit-card
-- totals match with allowed 10% positive deviation (0% negative)
-- invoice date in format "DD.MM." appears in the transaction purpose

-- 2f4a9197-a099-4068-802b-07ee1d3bc34d --

INSERT INTO matching.check (id, name)
    VALUES ('2f4a9197-a099-4068-802b-07ee1d3bc34d', 'Default 7');

INSERT INTO matching.check_transaction_type (check_id, transaction_type)
    VALUES ('2f4a9197-a099-4068-802b-07ee1d3bc34d', 'CREDIT_CARD');

INSERT INTO matching.check_totals (check_id, max_diff, diff_in_perc_from, diff_in_perc_to)
    VALUES ('2f4a9197-a099-4068-802b-07ee1d3bc34d', 100, 0, 0.10);

INSERT INTO matching.check_invoice_date_in_purpose (check_id, format)
    VALUES ('2f4a9197-a099-4068-802b-07ee1d3bc34d', 'DD.MM.');

----

-- totals match exactly
-- transaction partner is at least 3 characters long and is at least 65% similar to the invoice partner
-- dates are not more than 28 days apart (invoice date can be up to 14 days in the future)

-- 6af7c32c-9be4-486a-9cde-585ae7bfbe20 --

INSERT INTO matching.check (id, name)
    VALUES ('6af7c32c-9be4-486a-9cde-585ae7bfbe20', 'Default 8');

INSERT INTO matching.check_totals (check_id, max_diff, diff_in_perc_from, diff_in_perc_to)
    VALUES ('6af7c32c-9be4-486a-9cde-585ae7bfbe20', 0, 0, 0);

INSERT INTO matching.check_partner_names_similarity (check_id, min_len, similarity)
    VALUES ('6af7c32c-9be4-486a-9cde-585ae7bfbe20', 3, 0.65);

INSERT INTO matching.check_dates (check_id, diff_in_days_from, diff_in_days_to)
    VALUES ('6af7c32c-9be4-486a-9cde-585ae7bfbe20', -14, 28);

----

-- totals match with allowed 2% negative deviation and 10% positive deviation (with max total diff of 100)
-- transaction partner is at least 3 characters long and is at least 65% similar to the invoice partner
-- dates are not more than 6 days apart (invoice date must be before the transaction date)

-- 7a5210b4-cdde-423f-8a40-9f22e3662b87 --

INSERT INTO matching.check (id, name)
    VALUES ('7a5210b4-cdde-423f-8a40-9f22e3662b87', 'Default 9');

INSERT INTO matching.check_totals (check_id, max_diff, diff_in_perc_from, diff_in_perc_to)
    VALUES ('7a5210b4-cdde-423f-8a40-9f22e3662b87', 100, -0.02, 0.10);

INSERT INTO matching.check_partner_names_similarity (check_id, min_len, similarity)
    VALUES ('7a5210b4-cdde-423f-8a40-9f22e3662b87', 3, 0.65);

INSERT INTO matching.check_dates (check_id, diff_in_days_from, diff_in_days_to)
    VALUES ('7a5210b4-cdde-423f-8a40-9f22e3662b87', 0, 6);

----

-- transaction type is credit-card
-- totals match with allowed 5% negative deviation (0% positive)
-- transaction partner is at least 3 characters long and is at least 65% similar to the invoice partner
-- dates are not more than 3 days apart (invoice date can be up to 3 days in the future)

-- 9c23207f-06fd-440f-ac1c-824604144893 --

INSERT INTO matching.check (id, name)
    VALUES ('9c23207f-06fd-440f-ac1c-824604144893', 'Default 10');

INSERT INTO matching.check_transaction_type (check_id, transaction_type)
    VALUES ('9c23207f-06fd-440f-ac1c-824604144893', 'CREDIT_CARD');

INSERT INTO matching.check_totals (check_id, max_diff, diff_in_perc_from, diff_in_perc_to)
    VALUES ('9c23207f-06fd-440f-ac1c-824604144893', 999999, -0.05, 0);

INSERT INTO matching.check_partner_names_similarity (check_id, min_len, similarity)
    VALUES ('9c23207f-06fd-440f-ac1c-824604144893', 3, 0.65);

INSERT INTO matching.check_dates (check_id, diff_in_days_from, diff_in_days_to)
    VALUES ('9c23207f-06fd-440f-ac1c-824604144893', -3, 3);
