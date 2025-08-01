\echo
\echo '=== schema/tests/matching.sql ==='
\echo

---- Get invoice details by document ID: ----

-- SELECT (matching.invoice_derive_data_for_matching(invoice)).* FROM public.invoice WHERE document_id = '';

----

---- Get money transaction details by ID: ----

-- SELECT (matching.money_transaction_derive_data_for_matching(money_transaction)).* FROM public.money_transaction WHERE id = '';

----

do $$
DECLARE
    expected uuid;
    got      uuid;
BEGIN

    -- test-1 --
    expected := 'c2521919-d38b-44f2-a36b-acbb8eadbfb0';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -500, -- invoice_total
        '2018-91', -- invoice_number
        null, -- invoice_order_number
        '2018-09-11', -- invoice_date
        array['Derndinger GmbHDerndinger GmbH'], -- invoice_partner_name
        'DE03100208900019963284', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -500, -- transaction_total
        '2018-91 Derndinger GmbH', -- transaction_purpose
        '2018-09-17', -- transaction_date
        null, -- transaction_partner_name
        'DE03100208900019963284' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-1: expected % but got %', expected, got;
    END IF;

    -- test-2 --
    expected := '04dc7837-0e82-43d1-8d2f-deaecedfd8ec';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        558.3, -- invoice_total
        'RE18K99128', -- invoice_number
        null, -- invoice_order_number
        '2018-09-03', -- invoice_date
        array['Lanserhof GmbH'], -- invoice_partner_name
        'AT252011183728861100', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        558.3, -- transaction_total
        '/DOC/99128/558.30/20180903 Lanserhof GmbH', -- transaction_purpose
        '2018-09-18', -- transaction_date
        null, -- transaction_partner_name
        'AT273600000001041359' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-2: expected % but got %', expected, got;
    END IF;

    -- test-3 --
    expected := '04dc7837-0e82-43d1-8d2f-deaecedfd8ec';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        348.66, -- invoice_total
        'RE18K99121', -- invoice_number
        null, -- invoice_order_number
        '2018-09-03', -- invoice_date
        array['Steirer, Mika & Comp. Wirtschaftstreuhand GmbH'], -- invoice_partner_name
        'AT252011183728861100', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        348.66, -- transaction_total
        '99121 Steirer, Mika u. Comp. Wirtschaftst', -- transaction_purpose
        '2018-09-17', -- transaction_date
        null, -- transaction_partner_name
        'AT461200000405075904' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-3: expected % but got %', expected, got;
    END IF;

    -- test-4 --
    expected := '2f4a9197-a099-4068-802b-07ee1d3bc34d';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -76.08, -- invoice_total
        '1690-20180910-03-5063', -- invoice_number
        null, -- invoice_order_number
        '2018-09-10', -- invoice_date
        array['BillaBilla Aktiengesellschaft'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        -76.08, -- transaction_total
        'BILLA DANKT 1690 K1 10.09. 08:13', -- transaction_purpose
        '2018-09-10', -- transaction_date
        null, -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-4: expected % but got %', expected, got;
    END IF;

    -- test-5 --
    -- NOTE: disabled because invoice match algo does not match when just the totals fit
    -- expected := '';
    -- got := (SELECT matching.perform_checks(
    --     null,
    --     -- invoice
    --     666.66, -- invoice_total
    --     'RE18K99124', -- invoice_number
    --     null, -- invoice_order_number
    --     '2018-09-03', -- invoice_date
    --     array['KE Steuerberatungs GmbH'], -- invoice_partner_name
    --     'AT252011183728861100', -- invoice_partner_iban
    --     -- transaction
    --     'BANK', -- transaction_type
    --     666.66, -- transaction_total
    --     'KD18L999 ke steuerberatungsgmbh', -- transaction_purpose
    --     '2018-09-06', -- transaction_date
    --     null, -- transaction_partner_name
    --     'AT793500000000016253' -- transaction_partner_iban
    -- ));
    -- IF expected IS DISTINCT FROM got THEN
    --     RAISE EXCEPTION 'test-5: expected % but got %', expected, got;
    -- END IF;

    -- test-6 --
    expected := '2f4a9197-a099-4068-802b-07ee1d3bc34d';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -50.5, -- invoice_total
        '15117', -- invoice_number
        null, -- invoice_order_number
        '2018-09-05', -- invoice_date
        array['Bierraum GmbHBIERRAUM GmbH'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        -55, -- transaction_total
        'BIERRAUM 2310 K1 05.09. 15:57', -- transaction_purpose
        '2018-09-05', -- transaction_date
        null, -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-6: expected % but got %', expected, got;
    END IF;

    -- test-7 --
    expected := 'c2521919-d38b-44f2-a36b-acbb8eadbfb0';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -1320, -- invoice_total
        '26062018', -- invoice_number
        null, -- invoice_order_number
        '2018-06-26', -- invoice_date
        array['Magistrat der Stadt WienBundeshauptstadt Wien'], -- invoice_partner_name
        'AT911200051428018031', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -1320, -- transaction_total
        'DT: 83db72903fa54e8c9bb017cdedef7eb8 26062018', -- transaction_purpose
        '2018-09-04', -- transaction_date
        null, -- transaction_partner_name
        'AT911200051428018031' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-7: expected % but got %', expected, got;
    END IF;

    -- test-8 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        1856.71, -- invoice_total
        'RE18K9954', -- invoice_number
        null, -- invoice_order_number
        '2018-06-08', -- invoice_date
        array['ECOVIS Austria Wirschaftsprüfungs- und Steuerberatungs GmbH'], -- invoice_partner_name
        'AT252011183728861100', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        1856.71, -- transaction_total
        'Rg. RE 18K 9954 ECOVIS Austria Wirtschaftsprüfungs-', -- transaction_purpose
        '2018-08-14', -- transaction_date
        null, -- transaction_partner_name
        'AT241813054533110004' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-8: expected % but got %', expected, got;
    END IF;

    -- test-9 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -120, -- invoice_total
        '18/215', -- invoice_number
        null, -- invoice_order_number
        '2018-07-05', -- invoice_date
        array['Rechtsanwalts Kanzlei BauerMag. Bauer Herta Johanna'], -- invoice_partner_name
        'AT421952001800015552', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        120, -- transaction_total
        'Rücküberweisung wg. Verlegung der G Mag. Herta Bauer eschäftsanschrift wurde HN 18/215 s torniert.r', -- transaction_purpose
        '2018-08-03', -- transaction_date
        null, -- transaction_partner_name
        'AT421952001800015552' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-9: expected % but got %', expected, got;
    END IF;

    -- test-10 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -16.66, -- invoice_total
        '3455464262', -- invoice_number
        null, -- invoice_order_number
        '2018-04-30', -- invoice_date
        array['Google Ireland Limited'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        -16.66, -- transaction_total
        'GOOGLE  GSUITE_pinoli.', -- transaction_purpose
        '2018-08-02', -- transaction_date
        null, -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-10: expected % but got %', expected, got;
    END IF;

    -- test-11 --
    expected := 'c2521919-d38b-44f2-a36b-acbb8eadbfb0';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -825, -- invoice_total
        '262', -- invoice_number
        null, -- invoice_order_number
        '2018-08-23', -- invoice_date
        array['AustrianStartups"Austrianstartups" - Verein zur Sichtbarmachung der Start-up Community in Österreich'], -- invoice_partner_name
        'AT311420020010940690', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -825, -- transaction_total
        'DT: 1504fa92d85b46f9a5d9afc5c880d031 262', -- transaction_purpose
        '2018-09-21', -- transaction_date
        null, -- transaction_partner_name
        'AT311420020010940690' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-11: expected % but got %', expected, got;
    END IF;

    -- test-12 --
    expected := '7a5210b4-cdde-423f-8a40-9f22e3662b87';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -34.20, -- invoice_total
        'in-Db7SR9OHKEGgQh', -- invoice_number
        null, -- invoice_order_number
        '2018-09-13', -- invoice_date
        array['NOUN PROJECT'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        -34.97, -- transaction_total
        'NOUNPROJECT.COM inkl. Fremdwährungsentgelt 0,52 Kurs 1,1608127', -- transaction_purpose
        '2018-09-17', -- transaction_date
        null, -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-12: expected % but got %', expected, got;
    END IF;

    -- test-13 --
    expected := '6af7c32c-9be4-486a-9cde-585ae7bfbe20';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        58.9, -- invoice_total
        '201810005019', -- invoice_number
        null, -- invoice_order_number
        '2018-10-02', -- invoice_date
        array['Leierseder Barbara'], -- invoice_partner_name
        'AT873239700000810168', -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        58.9, -- transaction_total
        '5F871372T12379313', -- transaction_purpose
        '2018-10-10', -- transaction_date
        'Leierseder Barbara', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-13: expected % but got %', expected, got;
    END IF;

    -- test-14 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        666, -- invoice_total
        '201810020', -- invoice_number
        null, -- invoice_order_number
        '2018-01-11', -- invoice_date
        array['Auto Expo GmbH'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        680.4, -- transaction_total
        'ER00002001920180206002018020, 01, Ludwig Partner WP STB GmbH', -- transaction_purpose
        '2018-02-14', -- transaction_date
        'Ludwig Partner WP STB GmbH', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-14: expected % but got %', expected, got;
    END IF;

    -- test-15 --
    expected := '6af7c32c-9be4-486a-9cde-585ae7bfbe20';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        58.9, -- invoice_total
        '201810005019', -- invoice_number
        null, -- invoice_order_number
        '2018-10-02', -- invoice_date
        array['Leierseder Barbara'], -- invoice_partner_name
        'AT873239700000810168', -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        58.9, -- transaction_total
        '5F871372T12379313', -- transaction_purpose
        '2018-10-10', -- transaction_date
        'Barbara Leierseder', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-15: expected % but got %', expected, got;
    END IF;

    -- test-16 --
    expected := '6af7c32c-9be4-486a-9cde-585ae7bfbe20';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        93.9, -- invoice_total
        '201810005037', -- invoice_number
        null, -- invoice_order_number
        '2018-10-02', -- invoice_date
        array['Oberhorner Iris some irrelevant extra text'], -- invoice_partner_name
        'AT873239700000810168', -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        93.9, -- transaction_total
        '6B81543942229305W', -- transaction_purpose
        '2018-09-30', -- transaction_date
        'Iris Oberhorner', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-16: expected % but got %', expected, got;
    END IF;

    -- test-17 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        93.9, -- invoice_total
        '201810005037', -- invoice_number
        null, -- invoice_order_number
        '2018-10-16', -- invoice_date
        array['Doe JOHN'], -- invoice_partner_name
        'AT873239700000810168', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        93.9, -- transaction_total
        '6B81543942229305W', -- transaction_purpose
        '2018-10-01', -- transaction_date
        'JOHN Doe', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-17: expected % but got %', expected, got;
    END IF;

    -- test-18 --
    expected := '6af7c32c-9be4-486a-9cde-585ae7bfbe20';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        51, -- invoice_total
        '201810005024', -- invoice_number
        null, -- invoice_order_number
        '2018-10-02', -- invoice_date
        array['Ruppert von und zur Mühlen'], -- invoice_partner_name
        'AT873239700000810168', -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        51, -- transaction_total
        '7V7354476F696925N', -- transaction_purpose
        '2018-09-28', -- transaction_date
        'Ruppert von und zur Mühlen', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-18: expected % but got %', expected, got;
    END IF;

    -- test-19 --
    -- NOTE: disabled because invoice match algo does not match when just the totals fit
    -- expected := '';
    -- got := (SELECT matching.perform_checks(
    --     null,
    --     -- invoice
    --     348.6, -- invoice_total
    --     '201810005028', -- invoice_number
    --     null, -- invoice_order_number
    --     '2018-10-02', -- invoice_date
    --     array['Rohweder Leif'], -- invoice_partner_name
    --     'AT873239700000810168', -- invoice_partner_iban
    --     -- transaction
    --     'BANK', -- transaction_type
    --     348.6, -- transaction_total
    --     '0WH50270SX0742620', -- transaction_purpose
    --     '2018-09-30', -- transaction_date
    --     'Leif-Erik Rohweder', -- transaction_partner_name
    --     null -- transaction_partner_iban
    -- ));
    -- IF expected IS DISTINCT FROM got THEN
    --     RAISE EXCEPTION 'test-19: expected % but got %', expected, got;
    -- END IF;

    -- test-20 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -112.63, -- invoice_total
        'RE-2018/1859', -- invoice_number
        null, -- invoice_order_number
        '2018-12-13', -- invoice_date
        array['Druckerzone (Heiß Gernot) Heiß Gernot'], -- invoice_partner_name
        'AT202032602400000762', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -108.98, -- transaction_total
        'RE-2018/1731 Druckerzone', -- transaction_purpose
        '2019-01-03', -- transaction_date
        'Druckerzone', -- transaction_partner_name
        'AT202032602400000762' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-20: expected % but got %', expected, got;
    END IF;

    -- test-21 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -112.63, -- invoice_total
        'RE-2018/1859', -- invoice_number
        null, -- invoice_order_number
        '2018-12-13', -- invoice_date
        array['Druckerzone (Heiß Gernot) Heiß Gernot'], -- invoice_partner_name
        'AT202032602400000762', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -112.63, -- transaction_total
        'SEPA UEBERWEISUNG, Druckerzone, RE-2018/1859', -- transaction_purpose
        '2019-01-08', -- transaction_date
        'Druckerzone', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-21: expected % but got %', expected, got;
    END IF;

    -- test-22 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -1488.95, -- invoice_total
        '140065865', -- invoice_number
        null, -- invoice_order_number
        '2018-10-04', -- invoice_date
        array['IronMaxx Nutrition GmbH Ironmaxx Nutrition GmbH'], -- invoice_partner_name
        'DE41370700600333173300', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -1484.58, -- transaction_total
        '140059699 IronMaxx Nutrition GmbH', -- transaction_purpose
        '2018-10-24', -- transaction_date
        'IronMaxx Nutrition GmbH', -- transaction_partner_name
        'DE41370700600333173300' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-22: expected % but got %', expected, got;
    END IF;

    -- test-23 --
    expected := 'c2521919-d38b-44f2-a36b-acbb8eadbfb0';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -1488.95, -- invoice_total
        '140065865', -- invoice_number
        null, -- invoice_order_number
        '2018-10-04', -- invoice_date
        array['IronMaxx Nutrition GmbH Ironmaxx Nutrition GmbH'], -- invoice_partner_name
        'DE41370700600333173300', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -1478.56, -- transaction_total
        '140065865 - 150002067', -- transaction_purpose
        '2019-01-08', -- transaction_date
        'IronMaxx Nutrition GmbH', -- transaction_partner_name
        'DE41370700600333173300' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-23: expected % but got %', expected, got;
    END IF;

    -- test-24 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -361.2, -- invoice_total
        '8103106', -- invoice_number
        null, -- invoice_order_number
        '2018-10-26', -- invoice_date
        array['Barebells Functional Foods Barebells Funktional Foods Deutschland GmbH'], -- invoice_partner_name
        'DE36514206000012750006', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -348, -- transaction_total
        '8101163 Barebells Functional Foods', -- transaction_purpose
        '2018-11-22', -- transaction_date
        'Barebells Functional Foods', -- transaction_partner_name
        'DE36514206000012750006' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-24: expected % but got %', expected, got;
    END IF;

    -- test-25 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -361.2, -- invoice_total
        '8103106', -- invoice_number
        null, -- invoice_order_number
        '2018-10-26', -- invoice_date
        array['Barebells Functional Foods Barebells Funktional Foods Deutschland GmbH'], -- invoice_partner_name
        'DE36514206000012750006', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -361.2, -- transaction_total
        '8103106, Barebells Functional Foods Deutschl', -- transaction_purpose
        '2019-01-08', -- transaction_date
        'Barebells Functional Foods Deutschl', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-25: expected % but got %', expected, got;
    END IF;

    -- test-26 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -291.6, -- invoice_total
        '8103198', -- invoice_number
        null, -- invoice_order_number
        '2018-10-30', -- invoice_date
        array['Barebells Functional Foods Barebells Funktional Foods Deutschland GmbH'], -- invoice_partner_name
        'DE36514206000012750006', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -292, -- transaction_total
        '8101167 Barebells Functional Foods', -- transaction_purpose
        '2018-11-22', -- transaction_date
        'Barebells Functional Foods', -- transaction_partner_name
        'DE36514206000012750006' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-26: expected % but got %', expected, got;
    END IF;

    -- test-27 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -291.6, -- invoice_total
        '8103198', -- invoice_number
        null, -- invoice_order_number
        '2018-10-30', -- invoice_date
        array['Barebells Functional Foods Barebells Funktional Foods Deutschland GmbH'], -- invoice_partner_name
        'DE36514206000012750006', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -291.6, -- transaction_total
        '8103198, Barebells Functional Foods Deutschl', -- transaction_purpose
        '2019-01-08', -- transaction_date
        'Barebells Functional Foods Deutschl', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-27: expected % but got %', expected, got;
    END IF;

    -- test-28 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -591.6, -- invoice_total
        '8103753', -- invoice_number
        null, -- invoice_order_number
        '2018-11-30', -- invoice_date
        array['Barebells Functional Foods Barebells Funktional Foods Deutschland GmbH'], -- invoice_partner_name
        'DE36514206000012750006', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -600, -- transaction_total
        '8102183, Barebells Functional Foods Deutschl', -- transaction_purpose
        '2018-12-07', -- transaction_date
        'Barebells Functional Foods Deutschl', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-28: expected % but got %', expected, got;
    END IF;

    -- test-29 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -591.6, -- invoice_total
        '8103753', -- invoice_number
        null, -- invoice_order_number
        '2018-11-30', -- invoice_date
        array['Barebells Functional Foods Barebells Funktional Foods Deutschland GmbH'], -- invoice_partner_name
        'DE36514206000012750006', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -591.6, -- transaction_total
        '8103753, Barebells Functional Foods Deutschl', -- transaction_purpose
        '2019-01-08', -- transaction_date
        'Barebells Functional Foods Deutschl', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-29: expected % but got %', expected, got;
    END IF;

    -- test-30 --
    expected := 'bd2ddabf-88b6-4f69-ba55-1da4dcb5c1cc';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -27.9, -- invoice_total
        '201877697226', -- invoice_number
        null, -- invoice_order_number
        '2018-04-09', -- invoice_date
        array['Amazon EU S.á.r.l. Niederlassung Deutschland Amazon EU S.ar.l.'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        -27.9, -- transaction_total
        'CFiDq5ZbwXNrq6xR7 AEU-INV-DE-2018-77697226', -- transaction_purpose
        '2018-04-06', -- transaction_date
        'Amazon EU S.a r.l.', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-30: expected % but got %', expected, got;
    END IF;

    -- test-31 --
    expected := '6af7c32c-9be4-486a-9cde-585ae7bfbe20';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -27.9, -- invoice_total
        '201878537500', -- invoice_number
        null, -- invoice_order_number
        '2018-04-10', -- invoice_date
        array['Amazon EU S.á.r.l. Niederlassung Deutschland Amazon EU S.ar.l.'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        -27.9, -- transaction_total
        'CFiDq5ZbwXNrq6xR7 AEU-INV-DE-2018-77697226', -- transaction_purpose
        '2018-04-06', -- transaction_date
        'Amazon EU S.a r.l.', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-31: expected % but got %', expected, got;
    END IF;

    -- test-32 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -202.39, -- invoice_total
        '2S96758', -- invoice_number
        null, -- invoice_order_number
        '2018-03-21', -- invoice_date
        array['Scrum.org Scrum.org'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -203.49, -- transaction_total
        'ozyLvw9XgqqBYdNAa 2S96758', -- transaction_purpose
        '2018-03-28', -- transaction_date
        'Scrum Services', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-32: expected % but got %', expected, got;
    END IF;

    -- test-33 --
    expected := 'bd2ddabf-88b6-4f69-ba55-1da4dcb5c1cc';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -68.12, -- invoice_total
        '230871-2', -- invoice_number
        null, -- invoice_order_number
        '2018-03-19', -- invoice_date
        array['WirmachenDruck GmbH Wirmachendruck GmbH z.Hd.d.Geschf.'], -- invoice_partner_name
        'DE77622500300002102858', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -68.12, -- transaction_total
        '5bKhveu7EujS4LwGf 230871-2', -- transaction_purpose
        '2018-03-06', -- transaction_date
        'Www.Wir-Machen-Druck.D', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-33: expected % but got %', expected, got;
    END IF;

    -- test-34 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -154.7, -- invoice_total
        '1789201891', -- invoice_number
        null, -- invoice_order_number
        '2018-01-31', -- invoice_date
        array['Köln Kranhaus 1 Business Center GmbH & Co. KG Köln Kranhaus 1 Business Center GmbH & Co KG'], -- invoice_partner_name
        'DE46500109000019558013', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -154.7, -- transaction_total
        'pw7sfWSp7bxAQuoqQ 1789-2018-91INV', -- transaction_purpose
        '2018-02-19', -- transaction_date
        'Regus Kvln Kranhaus', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-34: expected % but got %', expected, got;
    END IF;

    -- test-35 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -108.74, -- invoice_total
        '4355201859', -- invoice_number
        null, -- invoice_order_number
        '2018-01-31', -- invoice_date
        array['RBC 13. Vorratsgesellschaft GmbH & Co KG RBC 13. Vorratsges. mbH & Co. KG'], -- invoice_partner_name
        'DE79500109000020463011', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -108.74, -- transaction_total
        'mNADZWfrvQSDoWdvL 4355-2018-591INV', -- transaction_purpose
        '2018-02-19', -- transaction_date
        'Bonn, Fgs Campus', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-35: expected % but got %', expected, got;
    END IF;

    -- test-36 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -129.71, -- invoice_total
        '242017901INV', -- invoice_number
        null, -- invoice_order_number
        '2018-01-01', -- invoice_date
        array['Regus Walldorf GmbH & Co KG Regus Walldorf Altrottstraße BC GmbH & Co KG'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -129.71, -- transaction_total
        'GXPmhdgCt5Qp4jGmc 0524-2017-901INV', -- transaction_purpose
        '2018-01-04', -- transaction_date
        'Regus Walldorf GmbH & Co. KG', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-36: expected % but got %', expected, got;
    END IF;

    -- test-37 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -810.264, -- invoice_total
        '310400169', -- invoice_number
        null, -- invoice_order_number
        '2019-01-31', -- invoice_date
        array['FUCHS AUSTRIA Schmierstoffe GmbH Fuchs Austria Schmierstoffe GmbH'], -- invoice_partner_name
        'AT841100000952959500', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -810.26, -- transaction_total
        'Rg. 310400169 Fuchs Austria', -- transaction_purpose
        '2019-02-11', -- transaction_date
        'Fuchs Austria', -- transaction_partner_name
        'AT111200000952959500' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-37: expected % but got %', expected, got;
    END IF;

    -- test-38 --
    expected := '5420b96a-b718-440b-91c4-2a9d8aa43d88';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        787.31, -- invoice_total
        '6551081', -- invoice_number
        null, -- invoice_order_number
        '2019-02-26', -- invoice_date
        array['Sax & Kratzer Schuster Sigrid'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        787.31, -- transaction_total
        '2000190308-2428502-0006849', -- transaction_purpose
        '2019-03-11', -- transaction_date
        'Sax & Kratzer e.U.', -- transaction_partner_name
        'AT143266700000072447' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-38: expected % but got %', expected, got;
    END IF;

    -- test-39 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        106.8, -- invoice_total
        null, -- invoice_number
        null, -- invoice_order_number
        '2019-03-12', -- invoice_date
        array[null], -- invoice_partner_name
        'AT252011183728861100', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        106.8, -- transaction_total
        '34000190227-5310255-0000442', -- transaction_purpose
        '2019-02-28', -- transaction_date
        'FireStart GmbH', -- transaction_partner_name
        'AT323413500007159460' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-39: expected % but got %', expected, got;
    END IF;

    -- test-40 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        58.8, -- invoice_total
        null, -- invoice_number
        null, -- invoice_order_number
        '2019-03-12', -- invoice_date
        array[null], -- invoice_partner_name
        'AT252011183728861100', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        58.8, -- transaction_total
        '34000190225-4680725-0001828', -- transaction_purpose
        '2019-02-26', -- transaction_date
        'Butleroy GmbH', -- transaction_partner_name
        'AT723427700002436749' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-40: expected % but got %', expected, got;
    END IF;

    -- test-41 --
    expected := '5420b96a-b718-440b-91c4-2a9d8aa43d88';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        3174.98, -- invoice_total
        '6551050', -- invoice_number
        null, -- invoice_order_number
        '2019-02-18', -- invoice_date
        array['Fruchtsäfte Schäfer Andreas Schäfer Andreas'], -- invoice_partner_name
        'AT272033400001152669', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        3174.98, -- transaction_total
        '140001903112FE10000005409469', -- transaction_purpose
        '2019-03-12', -- transaction_date
        'Andreas Schäfer', -- transaction_partner_name
        'AT751400003210900186' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-41: expected % but got %', expected, got;
    END IF;

    -- test-42 --
    expected := '7a5210b4-cdde-423f-8a40-9f22e3662b87';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        168.42, -- invoice_total
        '6551115', -- invoice_number
        null, -- invoice_order_number
        '2019-03-07', -- invoice_date
        array['TreibHouse Rene Jannach Jannach Rene'], -- invoice_partner_name
        'AT272033400001152669', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        168.24, -- transaction_total
        '202671903122CDC-00BCICGT84IW', -- transaction_purpose
        '2019-03-12', -- transaction_date
        'Rene Jannach', -- transaction_partner_name
        'AT212026702000095162' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-42: expected % but got %', expected, got;
    END IF;

    -- test-43 --
    -- NOTE: disabled because invoice match algo does not match when just the totals fit
    -- expected := '';
    -- got := (SELECT matching.perform_checks(
    --     null,
    --     -- invoice
    --     3024, -- invoice_total
    --     'R17001', -- invoice_number
    --     null, -- invoice_order_number
    --     '2017-02-13', -- invoice_date
    --     array['EDV-Software-Service GmbH U CO KG'], -- invoice_partner_name
    --     'AT881515000501277966', -- invoice_partner_iban
    --     -- transaction
    --     'BANK', -- transaction_type
    --     3024, -- transaction_total
    --     'UEBERWEISUNG, EDV-SOFTWARE-SERVICE, A-9500 VILLAC', -- transaction_purpose
    --     '2017-02-21', -- transaction_date
    --     'EDV-SOFTWARE-SERVICE, A-9500 VILLAC', -- transaction_partner_name
    --     null -- transaction_partner_iban
    -- ));
    -- IF expected IS DISTINCT FROM got THEN
    --     RAISE EXCEPTION 'test-43: expected % but got %', expected, got;
    -- END IF;

    -- test-44 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -680, -- invoice_total
        'INV-13512', -- invoice_number
        null, -- invoice_order_number
        '2019-04-26', -- invoice_date
        array['Baggage Hub Ltd Baggage Hub Ltd'], -- invoice_partner_name
        'GB93BARC20905623164403', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -680, -- transaction_total
        'SEPA-Überweisung an Connie HeiligersDuckers Verwendungszweck Pamono PM29122 a IBAN NL77INGB0009139332 BIC INGBNL2AXXX', -- transaction_purpose
        '2019-04-18', -- transaction_date
        'Connie HeiligersDuckers', -- transaction_partner_name
        'NL77INGB0009139332' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-44: expected % but got %', expected, got;
    END IF;

    -- test-45 --
    expected := '5420b96a-b718-440b-91c4-2a9d8aa43d88';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -65.59, -- invoice_total
        '62817', -- invoice_number
        null, -- invoice_order_number
        '2018-12-07', -- invoice_date
        array['Ehrenreich BaugmbH Ehrenreich Baugmbh'], -- invoice_partner_name
        'AT283506300000076414', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -65.59, -- transaction_total
        'SEPA-Lastschrift; Ehrenreich BaugmbH 5580 Tamsweg, Zinsgasse 9 IBAN: AT28 3506 3000 0007 6414 Creditor ID: AT08ZZZ00000016088 Mandatsnummer: Oberhummer Walter REF: 350001901160DATR173406321687', -- transaction_purpose
        '2019-01-18', -- transaction_date
        'Ehrenreich BaugmbH 5580', -- transaction_partner_name
        'AT283506300000076414' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-45: expected % but got %', expected, got;
    END IF;

    -- test-46 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        25.84, -- invoice_total
        '170', -- invoice_number
        null, -- invoice_order_number
        '2019-03-04', -- invoice_date
        array['Vens Nutrition Vens Nutrition e.U. Vens'], -- invoice_partner_name
        'AT073828200000070979', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        27.99, -- transaction_total
        'ABR 1704 EINR 0304-0304 100385327 1 MAS BR 28,35 DIS 0,22-ENTG 0,08-UST 0,06-; 201001904172AEI-CE10AULHITI3', -- transaction_purpose
        '2019-04-18', -- transaction_date
        'CARD COMPLETE SERVICE BANK AG', -- transaction_partner_name
        'AT792010040336604800' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-46: expected % but got %', expected, got;
    END IF;

    -- test-47 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        2353.49, -- invoice_total
        '700005030', -- invoice_number
        null, -- invoice_order_number
        '2019-03-26', -- invoice_date
        array['JTM Sportnahrung GmbH JTM Sportnahrung GmbH'], -- invoice_partner_name
        'DE25700100800647459804', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        2400, -- transaction_total
        'Gutschrift Onlinebanking BG/000032163 BAWAATWWXXX AT546000000510038371 Sporternährung Mitteregger Gmb H Eigenübertrag', -- transaction_purpose
        '2019-04-12', -- transaction_date
        'Sporternährung Mitteregger', -- transaction_partner_name
        'AT546000000510038371' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-47: expected % but got %', expected, got;
    END IF;

    -- test-48 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -570.58, -- invoice_total
        'FS-921/19', -- invoice_number
        null, -- invoice_order_number
        '2019-02-06', -- invoice_date
        array['Olimp-Germany Olimp Laboratories'], -- invoice_partner_name
        'DE43200300000001518950', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -598.44, -- transaction_total
        'FS-9319/18, OLIMP Laboratories Germany', -- transaction_purpose
        '2019-01-30', -- transaction_date
        'OLIMP Laboratories Germany', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-48: expected % but got %', expected, got;
    END IF;

    -- test-49 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -959.52, -- invoice_total
        'FS-1422/19', -- invoice_number
        null, -- invoice_order_number
        '2019-02-26', -- invoice_date
        array['Olimp-Germany Olimp Laboratories'], -- invoice_partner_name
        'DE43200300000001518950', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -968.08, -- transaction_total
        'SEPA UEBERWEISUNG, OLIMP Laboratories Germany, FS-9994/18', -- transaction_purpose
        '2019-02-21', -- transaction_date
        'OLIMP Laboratories Germany', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-49: expected % but got %', expected, got;
    END IF;

    -- test-50 --
    expected := NULL;
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -2987.76, -- invoice_total
        'FS-1500/19', -- invoice_number
        null, -- invoice_order_number
        '2019-03-01', -- invoice_date
        array['Olimp-Germany Olimp Laboratories'], -- invoice_partner_name
        'DE43200300000001518950', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -3043.36, -- transaction_total
        'CNR/2601904/DOC/66/3043.36/20190301; 1200019022811443113783402193', -- transaction_purpose
        '2019-03-11', -- transaction_date
        'Südpark Betriebs- und Verwaltungs GmbH', -- transaction_partner_name
        'AT711200052969001325' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-50: expected % but got %', expected, got;
    END IF;

    -- test-51 --
    expected := '2f4a9197-a099-4068-802b-07ee1d3bc34d';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -63.25, -- invoice_total
        '1690-20181217-03-1236', -- invoice_number
        null, -- invoice_order_number
        '2018-12-17', -- invoice_date
        array['Billa Billa Aktiengesellschaft'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        -63.25, -- transaction_total
        'BILLA DANKT 2320 K1 17.12. 08:15; 201111812172ALB-0081FH4ALPSG', -- transaction_purpose
        '2018-12-17', -- transaction_date
        'BILLA DANKT', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-51: expected % but got %', expected, got;
    END IF;

    -- test-52 --
    expected := '6af7c32c-9be4-486a-9cde-585ae7bfbe20';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -13.5848386313298, -- invoice_total
        'INV08955704', -- invoice_number
        null, -- invoice_order_number
        '2019-10-15', -- invoice_date
        array['Zoom Video Communications Inc. Zoom Video Communications Inc.'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        -13.5848386313298, -- transaction_total
        'zoom.us', -- transaction_purpose
        '2019-10-15', -- transaction_date
        null, -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-52: expected % but got %', expected, got;
    END IF;

    -- test-53 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -11617.22, -- invoice_total
        '30004183', -- invoice_number
        null, -- invoice_order_number
        '2020-01-18', -- invoice_date
        array['DK Company CPH A/S DK Company Cph A/S'], -- invoice_partner_name
        'DE46203205004989183680', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -11152.53, -- transaction_total
        '30004183', -- transaction_purpose
        '2020-02-21', -- transaction_date
        'DK Company CPH A/S', -- transaction_partner_name
        'DE46203205004989183680' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-53: expected % but got %', expected, got;
    END IF;

    -- test-54 --
    expected := '691d54db-2ab1-4f47-a2d9-3a1760805e65';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        189, -- invoice_total
        'RE19/00716', -- invoice_number
        null, -- invoice_order_number
        '2020-01-01', -- invoice_date
        array['Pamono GmbH Pamono GmbH'], -- invoice_partner_name
        'AT252011183728861100', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        189, -- transaction_total
        'RE19-00716; 201002002252AEI-58XKAZ000663', -- transaction_purpose
        '2020-02-25', -- transaction_date
        'Pamono GmbH', -- transaction_partner_name
        'DE30100700240137868600' -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-54: expected % but got %', expected, got;
    END IF;

    -- test-55 --
    expected := '6af7c32c-9be4-486a-9cde-585ae7bfbe20';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        200, -- invoice_total
        '123456', -- invoice_number
        null, -- invoice_order_number
        '2020-01-01', -- invoice_date
        array['John Doe'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        200, -- transaction_total
        '201002002252AEI-58XKAZ000663', -- transaction_purpose
        '2020-01-01', -- transaction_date
        'Doe John <john@doe.com>', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-55: expected % but got %', expected, got;
    END IF;

    -- test-56 --
    expected := 'bd2ddabf-88b6-4f69-ba55-1da4dcb5c1cc';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -68.12, -- invoice_total
        null, -- invoice_number
        '230871-2', -- invoice_order_number
        '2018-03-19', -- invoice_date
        array['WirmachenDruck GmbH Wirmachendruck GmbH z.Hd.d.Geschf.'], -- invoice_partner_name
        'DE77622500300002102858', -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -68.12, -- transaction_total
        '5bKhveu7EujS4LwGf 230871-2', -- transaction_purpose
        '2018-03-06', -- transaction_date
        'Www.Wir-Machen-Druck.D', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-56: expected % but got %', expected, got;
    END IF;

    -- test-57 --
    expected := 'bd2ddabf-88b6-4f69-ba55-1da4dcb5c1cc';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -27.9, -- invoice_total
        null, -- invoice_number
        '201877697226', -- invoice_order_number
        '2018-04-09', -- invoice_date
        array['Amazon EU S.á.r.l. Niederlassung Deutschland Amazon EU S.ar.l.'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        -27.9, -- transaction_total
        'CFiDq5ZbwXNrq6xR7 AEU-INV-DE-2018-77697226', -- transaction_purpose
        '2018-04-06', -- transaction_date
        'Amazon EU S.a r.l.', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-57: expected % but got %', expected, got;
    END IF;

    -- test-58 --
    expected := 'bd2ddabf-88b6-4f69-ba55-1da4dcb5c1cc';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -27.9, -- invoice_total
        'IDontAppearAnywhere', -- invoice_number
        '201877697226', -- invoice_order_number
        '2018-04-09', -- invoice_date
        array['Amazon EU S.á.r.l. Niederlassung Deutschland Amazon EU S.ar.l.'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        -27.9, -- transaction_total
        'CFiDq5ZbwXNrq6xR7 AEU-INV-DE-2018-77697226', -- transaction_purpose
        '2018-04-06', -- transaction_date
        'Amazon EU S.a r.l.', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-58: expected % but got %', expected, got;
    END IF;

    -- test-59 --
    expected := '5420b96a-b718-440b-91c4-2a9d8aa43d88';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        -34.33, -- invoice_total
        '7625', -- invoice_number
        null, -- invoice_order_number
        '2022-10-18', -- invoice_date
        array['Billa AG'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'BANK', -- transaction_type
        -34.33, -- transaction_total
        'BILLA DANKT 2320 K2 18.10. 08:48; 201112210182ALB-008G70V56RNC', -- transaction_purpose
        '2022-10-18', -- transaction_date
        'BILLA DANKT', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-59: expected % but got %', expected, got;
    END IF;

    -- test-60 --
    expected := '6af7c32c-9be4-486a-9cde-585ae7bfbe20';
    got := (SELECT matching.perform_checks(
        null,
        -- invoice
        200, -- invoice_total
        '123456', -- invoice_number
        null, -- invoice_order_number
        '2020-01-01', -- invoice_date
        array['Not A Person', 'John Doe'], -- invoice_partner_name
        null, -- invoice_partner_iban
        -- transaction
        'CREDIT_CARD', -- transaction_type
        200, -- transaction_total
        '201002002252AEI-58XKAZ000663', -- transaction_purpose
        '2020-01-01', -- transaction_date
        'Doe John <john@doe.com>', -- transaction_partner_name
        null -- transaction_partner_iban
    ));
    IF expected IS DISTINCT FROM got THEN
        RAISE EXCEPTION 'test-60: expected % but got %', expected, got;
    END IF;

END;
$$
