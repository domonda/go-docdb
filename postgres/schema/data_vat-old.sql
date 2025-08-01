\echo
\echo '=== data_vat.sql ==='
\echo

--
-- payable
--

-- at
insert into public.value_added_tax (id, "type", name, short_name, vat_id_required, country)
    values ('52475137-cb50-403e-bc31-3cf3ae079129', 'PAYABLE', 'Umsatzsteuer', 'UST', false, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('a6482f5f-8391-4a1f-9fa4-368ae1c6a785', '52475137-cb50-403e-bc31-3cf3ae079129', 5);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('bfa4a097-b6a7-4203-b8ee-872bd1f9600d', '52475137-cb50-403e-bc31-3cf3ae079129', 10);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('bfa4a097-b6a7-4203-b8ee-872bd1f9600d', 'DATEV', true, '2');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('0f9ec62c-b4ae-47b1-a553-3169b36ddc18', '52475137-cb50-403e-bc31-3cf3ae079129', 13);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('0f9ec62c-b4ae-47b1-a553-3169b36ddc18', 'DATEV', true, '4');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('2d919a0a-368b-4582-9047-dac1bb3d9fac', '52475137-cb50-403e-bc31-3cf3ae079129', 20);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('2d919a0a-368b-4582-9047-dac1bb3d9fac', 'DATEV', true, '3');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('52475137-cb50-403e-bc31-3cf3ae079129', 'BMD', true, '1');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('52475137-cb50-403e-bc31-3cf3ae079129', 'DVO', true, '1');
insert into public.value_added_tax_code(id, value_added_tax_id, accounting_system, reclaimable, code)
    values ('fdfa858f-545b-4789-8ac2-b434ad4037e3', '52475137-cb50-403e-bc31-3cf3ae079129', 'RZL', true, '2');

-- de
insert into public.value_added_tax (id, "type", name, short_name, vat_id_required, country)
    values ('268bea24-0add-4213-a70c-3010f10e4ec9', 'PAYABLE', 'Umsatzsteuer', 'UST', false, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('79f4dd94-1c7d-47aa-a661-5957c36320f4', '268bea24-0add-4213-a70c-3010f10e4ec9', 5);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('79f4dd94-1c7d-47aa-a661-5957c36320f4', 'DATEV', true, '4');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('00e222f4-a3e2-4780-9f70-edb09dc9d705', '268bea24-0add-4213-a70c-3010f10e4ec9', 7);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('00e222f4-a3e2-4780-9f70-edb09dc9d705', 'DATEV', true, '2');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('f1c781d4-1666-4b26-8cbb-ea9ea11d6bb9', '268bea24-0add-4213-a70c-3010f10e4ec9', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('f1c781d4-1666-4b26-8cbb-ea9ea11d6bb9', 'DATEV', true, '5');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('6f13f42b-8708-4fa9-a3be-6caa6ed3a77a', '268bea24-0add-4213-a70c-3010f10e4ec9', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('6f13f42b-8708-4fa9-a3be-6caa6ed3a77a', 'DATEV', true, '3');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('268bea24-0add-4213-a70c-3010f10e4ec9', 'BMD', true, '1');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('268bea24-0add-4213-a70c-3010f10e4ec9', 'DVO', true, '1');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('03b3a9fb-12f9-486e-8c2a-0e2fd658f5af', 'PAYABLE', 'Ausfuhrlieferungen', 'UST AL', true, false, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('03b3a9fb-12f9-486e-8c2a-0e2fd658f5af', 'BMD', true, '5');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('03b3a9fb-12f9-486e-8c2a-0e2fd658f5af', 'DVO', true, '5');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('03b3a9fb-12f9-486e-8c2a-0e2fd658f5af', 'DATEV', true, '1');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('c4bcbd89-532d-45e9-a81f-addb3b170127', 'PAYABLE', 'Ausfuhrlieferungen', 'UST AL', true, false, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('c4bcbd89-532d-45e9-a81f-addb3b170127', 'DATEV', true, '1');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('626772c4-87ee-4d97-9f56-6fb7017753e8', 'PAYABLE', 'Dienstleisutng iVm Ausfuhr', 'UST AL DL', true, false, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('626772c4-87ee-4d97-9f56-6fb7017753e8', 'BMD', true, '20');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('626772c4-87ee-4d97-9f56-6fb7017753e8', 'DVO', true, '20');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('626772c4-87ee-4d97-9f56-6fb7017753e8', 'DATEV', true, '1');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('38872f7e-c741-4bb5-8028-84b8f1c65cad', 'PAYABLE', 'Dienstleisutng iVm Ausfuhr', 'UST AL DL', true, false, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('38872f7e-c741-4bb5-8028-84b8f1c65cad', 'DATEV', true, '1');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('898cfd35-2c1f-4733-adc7-c934edd3e8a8', 'PAYABLE', 'Dreiecksgeschäft', 'UST DEG1', true, true, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('898cfd35-2c1f-4733-adc7-c934edd3e8a8', 'BMD', true, '6');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('898cfd35-2c1f-4733-adc7-c934edd3e8a8', 'DVO', true, '6');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('d7c26561-a4f1-4c2b-bdc9-9da755c03994', 'PAYABLE', 'Dreiecksgeschäft', 'UST DEG1', true, true, 'DE');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('906f0273-0a92-4ad7-bd0a-12b045307055', 'PAYABLE', 'Lohnveredelung iVm Ausfuhr', 'UST AL LV', true, false, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('906f0273-0a92-4ad7-bd0a-12b045307055', 'BMD', true, '13');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('906f0273-0a92-4ad7-bd0a-12b045307055', 'DVO', true, '13');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('906f0273-0a92-4ad7-bd0a-12b045307055', 'DATEV', true, '1');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('97fbe0fb-076f-4c27-aa08-e453551e4557', 'PAYABLE', 'Lohnveredelung iVm Ausfuhr', 'UST AL LV', true, false, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('97fbe0fb-076f-4c27-aa08-e453551e4557', 'DATEV', true, '1');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, vat_id_required, country)
    values ('a989609c-21db-4ef1-bf0d-231d45461e80', 'PAYABLE', 'Personenbeförderung', 'UST Pers', false, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('3da801b3-d90d-4281-b55d-cc41b9642876', 'a989609c-21db-4ef1-bf0d-231d45461e80', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('a989609c-21db-4ef1-bf0d-231d45461e80', 'BMD', true, '14');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('a989609c-21db-4ef1-bf0d-231d45461e80', 'DVO', true, '14');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('9e55209b-577a-4f36-b737-2c22449fe81e', 'PAYABLE', 'Grundstücksumsätze', 'UST Grund', true, false, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('9e55209b-577a-4f36-b737-2c22449fe81e', 'BMD', true, '15');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('9e55209b-577a-4f36-b737-2c22449fe81e', 'DVO', true, '15');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('767f2e92-f97d-43d8-a4d3-e7a80045b4ca', 'PAYABLE', 'Grundstücksumsätze', 'UST Grund', true, false, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('767f2e92-f97d-43d8-a4d3-e7a80045b4ca', 'BMD', true, '24');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('767f2e92-f97d-43d8-a4d3-e7a80045b4ca', 'DVO', true, '24');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('373c9d73-ca2e-4653-8521-a0ba0c48811c', 'PAYABLE', 'Kleinunternehmer', 'UST KU', true, false, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('373c9d73-ca2e-4653-8521-a0ba0c48811c', 'BMD', false, '16');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('373c9d73-ca2e-4653-8521-a0ba0c48811c', 'DVO', false, '16');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('0718778c-a6b4-4583-adca-046d5931876b', 'PAYABLE', 'Umsatz aus Lieferung nicht steuerbar', 'UST Lief. n.sb.', true, false, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('0718778c-a6b4-4583-adca-046d5931876b', 'BMD', true, '81');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('0718778c-a6b4-4583-adca-046d5931876b', 'DVO', true, '81');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('ec41a564-9337-4c00-be25-824c83c1d209', 'PAYABLE', 'Umsatz aus Lieferung nicht steuerbar', 'UST Lief. n.sb.', true, false, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('ec41a564-9337-4c00-be25-824c83c1d209', 'BMD', true, '81');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('ec41a564-9337-4c00-be25-824c83c1d209', 'DVO', true, '81');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('58ed6729-5e94-4101-8f8b-352111c53ff7', 'PAYABLE', 'Umsatz aus Leistung nicht steuerbar', 'UST Leis. n.sb.', true, false, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('58ed6729-5e94-4101-8f8b-352111c53ff7', 'BMD', true, '82');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('58ed6729-5e94-4101-8f8b-352111c53ff7', 'DVO', true, '82');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('2d369849-9b49-455f-a734-3b55987cab16', 'PAYABLE', 'innergemeinschaftliche Lieferung', 'igL', true, true, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('2d369849-9b49-455f-a734-3b55987cab16', 'BMD', true, '7');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('2d369849-9b49-455f-a734-3b55987cab16', 'DVO', true, '7');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('2d369849-9b49-455f-a734-3b55987cab16', 'DATEV', true, '11');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('4e143f18-bc16-48c1-bf1d-1e1609fbbadc', 'PAYABLE', 'innergemeinschaftliche Lieferung', 'igL', true, true, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('4e143f18-bc16-48c1-bf1d-1e1609fbbadc', 'BMD', true, '7');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('4e143f18-bc16-48c1-bf1d-1e1609fbbadc', 'DVO', true, '7');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('4e143f18-bc16-48c1-bf1d-1e1609fbbadc', 'DATEV', true, '11');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('610eda2e-4dce-46cf-81af-4d38cfe1db1e', 'PAYABLE', 'Reverse Charge Ausgang', 'RC UST', true, true, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('610eda2e-4dce-46cf-81af-4d38cfe1db1e', 'BMD', true, '77');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('610eda2e-4dce-46cf-81af-4d38cfe1db1e', 'DVO', true, '77');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('610eda2e-4dce-46cf-81af-4d38cfe1db1e', 'DATEV', true, '47');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('d053ec47-27d1-4d92-b484-596e33789f3a', 'PAYABLE', 'Reverse Charge Ausgang', 'U RC', true, true, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('d053ec47-27d1-4d92-b484-596e33789f3a', 'BMD', true, '77');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('d053ec47-27d1-4d92-b484-596e33789f3a', 'DVO', true, '77');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('d053ec47-27d1-4d92-b484-596e33789f3a', 'DATEV', true, '47');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('0d99d941-245c-4b25-823b-2f499c38ce11', 'PAYABLE', 'Nicht steuerbare Umsätze §19/1', 'RC 19/1', true, true, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('0d99d941-245c-4b25-823b-2f499c38ce11', 'BMD', true, '64');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('0d99d941-245c-4b25-823b-2f499c38ce11', 'DVO', true, '64');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('5be0fc7d-9285-472e-90b6-99a154631a14', 'PAYABLE', 'Umsatz RC Bauleistung', 'U RC 19/1a', true, true, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('5be0fc7d-9285-472e-90b6-99a154631a14', 'BMD', true, '27');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('5be0fc7d-9285-472e-90b6-99a154631a14', 'DVO', true, '27');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('5be0fc7d-9285-472e-90b6-99a154631a14', 'DATEV', true, '46');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('457f3613-c08c-46c5-a448-ba9641c00ce7', 'PAYABLE', 'Umsätze §19/1a', 'U RC 13/2 Nr.4', true, true, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('457f3613-c08c-46c5-a448-ba9641c00ce7', 'BMD', true, '27');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('457f3613-c08c-46c5-a448-ba9641c00ce7', 'DVO', true, '27');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('457f3613-c08c-46c5-a448-ba9641c00ce7', 'DATEV', true, '46');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('806e79ea-cd47-4aa6-a435-8e4f538fbc6e', 'PAYABLE', 'Umsatz RC Sicherungsübereignung', 'U RC 19/1b', true, true, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('806e79ea-cd47-4aa6-a435-8e4f538fbc6e', 'BMD', true, '21');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('806e79ea-cd47-4aa6-a435-8e4f538fbc6e', 'DVO', true, '21');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('806e79ea-cd47-4aa6-a435-8e4f538fbc6e', 'DATEV', true, '46');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('f93c27f5-30d1-470c-a313-5bab130144b6', 'PAYABLE', 'Umsatz RC Sicherungsübereignung', 'U RC 13/2 Nr.2', true, true, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('f93c27f5-30d1-470c-a313-5bab130144b6', 'DATEV', true, '46');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('ba427baf-72a7-4cae-8b40-84ac5ff0e276', 'PAYABLE', 'Umsatz RC Gas & Elektrizität', 'U RC 19/1c', true, true, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('ba427baf-72a7-4cae-8b40-84ac5ff0e276', 'BMD', true, '24');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('ba427baf-72a7-4cae-8b40-84ac5ff0e276', 'DVO', true, '24');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('ba427baf-72a7-4cae-8b40-84ac5ff0e276', 'DATEV', true, '46');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('580a446c-f4bb-4816-883c-e09b7678ded6', 'PAYABLE', 'Umsatz RC Gas & Elektrizität', 'U RC 13/2 Nr.5', true, true, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('580a446c-f4bb-4816-883c-e09b7678ded6', 'DATEV', true, '46');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('ef7d3c27-dfb9-4f00-a55d-a3f020c41e97', 'PAYABLE', 'Umsatz RC Schrott & Altmetall', 'U RC 19/1d Schrott', true, true, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('ef7d3c27-dfb9-4f00-a55d-a3f020c41e97', 'BMD', true, '57');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('ef7d3c27-dfb9-4f00-a55d-a3f020c41e97', 'DVO', true, '57');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('ef7d3c27-dfb9-4f00-a55d-a3f020c41e97', 'DATEV', true, '46');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('c097991b-9cb2-4a1c-80f8-f59941c8d50c', 'PAYABLE', 'Umsatz RC Schrott & Altmetall', 'U RC 13/2 Nr.7', true, true, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('c097991b-9cb2-4a1c-80f8-f59941c8d50c', 'BMD', true, '57');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('c097991b-9cb2-4a1c-80f8-f59941c8d50c', 'DVO', true, '57');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('c097991b-9cb2-4a1c-80f8-f59941c8d50c', 'DATEV', true, '46');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('63df9fdd-34eb-4854-81de-d944f72bb5a8', 'PAYABLE', 'Umsatz RC Treibhausgas & Mobilfunk', 'U RC 19/1e', true, true, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('63df9fdd-34eb-4854-81de-d944f72bb5a8', 'BMD', true, '87');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('63df9fdd-34eb-4854-81de-d944f72bb5a8', 'DVO', true, '87');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('63df9fdd-34eb-4854-81de-d944f72bb5a8', 'DATEV', true, '46');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('2eae60ea-c50c-44fb-9842-7da0cb826c45', 'PAYABLE', 'Umsatz RC Treibhausgas & Mobilfunk', 'U RC 13/2 Nr.6', true, true, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('2eae60ea-c50c-44fb-9842-7da0cb826c45', 'DATEV', true, '46');

----

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('fdc77ded-af73-4602-903e-e9f11195cf47', 'PAYABLE', 'Umsatz RC Mobilfunk', 'U RC 13/2 Nr. 10', true, true, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('fdc77ded-af73-4602-903e-e9f11195cf47', 'DATEV', true, '201');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('8cbc9d18-5b44-4ce9-89bd-fce4c6781349', 'PAYABLE', 'Elektronische Dienstleistungen - MOSS', 'MOSS', true, false, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('8cbc9d18-5b44-4ce9-89bd-fce4c6781349', 'DATEV', true, '44');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('21e132b9-6345-4821-875b-9630b1cfab52', 'PAYABLE', 'Elektronische Dienstleistungen - MOSS', 'MOSS', true, false, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('21e132b9-6345-4821-875b-9630b1cfab52', 'DATEV', true, '44');

--
-- reclaimable
--

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, vat_id_required, country)
    values ('66e9bce0-55aa-45a6-b388-03f885772cff', 'RECLAIMABLE', 'Vorsteuer', 'VST', false, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('78f31165-8426-441f-9249-2f91172e5b61', '66e9bce0-55aa-45a6-b388-03f885772cff', 5);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('7634e886-ffde-41d0-9d61-c02cf4c667ea', '66e9bce0-55aa-45a6-b388-03f885772cff', 10);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('7634e886-ffde-41d0-9d61-c02cf4c667ea', 'DATEV', true, '8');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('3034f7db-1ae6-4090-8b35-563410883b69', '66e9bce0-55aa-45a6-b388-03f885772cff', 13);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('3034f7db-1ae6-4090-8b35-563410883b69', 'DATEV', true, '6');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('577810be-95b7-410b-9589-daa34c192a0e', '66e9bce0-55aa-45a6-b388-03f885772cff', 20);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('577810be-95b7-410b-9589-daa34c192a0e', 'DATEV', true, '9');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('66e9bce0-55aa-45a6-b388-03f885772cff', 'BMD', true, '2');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('66e9bce0-55aa-45a6-b388-03f885772cff', 'DVO', true, '2');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('66e9bce0-55aa-45a6-b388-03f885772cff', 'BMD', false, '42');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('66e9bce0-55aa-45a6-b388-03f885772cff', 'DVO', false, '42');
insert into public.value_added_tax_code(id, value_added_tax_id, accounting_system, reclaimable, code)
    values ('66a28365-3a27-484a-9029-cf76566a0e84', '66e9bce0-55aa-45a6-b388-03f885772cff', 'RZL', false, '1');

-- de
insert into public.value_added_tax (id, "type", name, short_name, vat_id_required, country)
    values ('649927ac-81c8-4680-89f2-0a3033f19546', 'RECLAIMABLE', 'Vorsteuer', 'VST', false, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('819727d6-ee76-47b0-a0ff-cb7aa8c2f29e', '649927ac-81c8-4680-89f2-0a3033f19546', 5);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('819727d6-ee76-47b0-a0ff-cb7aa8c2f29e', 'DATEV', true, '6');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('00e084f6-a852-48e9-91d1-c7738524cb80', '649927ac-81c8-4680-89f2-0a3033f19546', 7);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('00e084f6-a852-48e9-91d1-c7738524cb80', 'DATEV', true, '8');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('10ee5f80-78bc-4090-932c-6daccbd37cb0', '649927ac-81c8-4680-89f2-0a3033f19546', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('10ee5f80-78bc-4090-932c-6daccbd37cb0', 'DATEV', true, '7');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('09047331-e649-4f4d-a92e-ef52da04c301', '649927ac-81c8-4680-89f2-0a3033f19546', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('09047331-e649-4f4d-a92e-ef52da04c301', 'DATEV', true, '9');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('649927ac-81c8-4680-89f2-0a3033f19546', 'BMD', true, '2');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('649927ac-81c8-4680-89f2-0a3033f19546', 'DVO', true, '2');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('649927ac-81c8-4680-89f2-0a3033f19546', 'BMD', false, '42');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('649927ac-81c8-4680-89f2-0a3033f19546', 'DVO', false, '42');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, vat_id_required, country)
    values ('b46b1b19-82d2-4d25-b777-b202bb6d13b3', 'RECLAIMABLE', 'Einfuhrumsatzsteuer', 'EUST', false, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('1c0bbadb-c7e1-46f1-a33f-2781d14549cc', 'b46b1b19-82d2-4d25-b777-b202bb6d13b3', 5);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('6196576f-8a54-4a1c-bfd0-200e56c81cc3', 'b46b1b19-82d2-4d25-b777-b202bb6d13b3', 10);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('9106c6f6-2962-4764-9e5e-337e49ed412d', 'b46b1b19-82d2-4d25-b777-b202bb6d13b3', 13);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('c1eead78-a652-4a1b-8b11-b729ec99f327', 'b46b1b19-82d2-4d25-b777-b202bb6d13b3', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('b46b1b19-82d2-4d25-b777-b202bb6d13b3', 'BMD', true, '34');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('b46b1b19-82d2-4d25-b777-b202bb6d13b3', 'DVO', true, '34');

-- de
insert into public.value_added_tax (id, "type", name, short_name, vat_id_required, country)
    values ('6c1dd50c-1b62-4fc6-981d-05bca682589e', 'RECLAIMABLE', 'Einfuhrumsatzsteuer', 'EUST', false, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('9c05cb7a-930f-4388-aef2-1c576828cf58', '6c1dd50c-1b62-4fc6-981d-05bca682589e', 5);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('1b3a0f4c-3aae-42b8-b874-1bec1cddcdf3', '6c1dd50c-1b62-4fc6-981d-05bca682589e', 7);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('ab495a0f-ac48-4ee9-8b06-f835d8797ffc', '6c1dd50c-1b62-4fc6-981d-05bca682589e', 16);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('8d53ff57-8356-4383-a53d-f0f297ffb424', '6c1dd50c-1b62-4fc6-981d-05bca682589e', 19);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('6c1dd50c-1b62-4fc6-981d-05bca682589e', 'BMD', true, '34');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('6c1dd50c-1b62-4fc6-981d-05bca682589e', 'DVO', true, '34');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, vat_id_required, country)
    values ('b510fee8-b2a4-48c5-b0b5-1e8310dbaeb8', 'RECLAIMABLE', 'Einfuhrumsatzsteuer auf Abgabenkonto', 'EUST AK', false, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('fa083be2-2df4-4b11-bf0d-7d53dc4d2646', 'b510fee8-b2a4-48c5-b0b5-1e8310dbaeb8', 5);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('7e71ecd2-6a65-4f82-8a97-d5f2a47c8b94', 'b510fee8-b2a4-48c5-b0b5-1e8310dbaeb8', 10);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('f6431add-f6aa-45b6-848e-53cd4bf952aa', 'b510fee8-b2a4-48c5-b0b5-1e8310dbaeb8', 13);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('d23d28be-7fe7-441e-a643-705240c72065', 'b510fee8-b2a4-48c5-b0b5-1e8310dbaeb8', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('b510fee8-b2a4-48c5-b0b5-1e8310dbaeb8', 'BMD', true, '35');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('b510fee8-b2a4-48c5-b0b5-1e8310dbaeb8', 'DVO', true, '35');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, vat_id_required, country)
    values ('3226c276-45ca-4af7-a262-df3e03969748', 'RECLAIMABLE', 'Einfuhrumsatzsteuer gesch. §12/1 Z 2 lit. B', 'UST §12 l.sb.', false, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('42a5acff-ebf2-435a-a441-1cccb533db61', '3226c276-45ca-4af7-a262-df3e03969748', 5);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('8c3dd49b-2af5-4ab6-8c31-d44be25ed307', '3226c276-45ca-4af7-a262-df3e03969748', 10);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('b635f8af-dad9-41fb-a565-3549e5c50139', '3226c276-45ca-4af7-a262-df3e03969748', 13);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('19426e6b-0f43-40ce-ba53-5a72b5219e59', '3226c276-45ca-4af7-a262-df3e03969748', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('3226c276-45ca-4af7-a262-df3e03969748', 'BMD', true, '36');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('3226c276-45ca-4af7-a262-df3e03969748', 'DVO', true, '36');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('52eb0ebd-f5bf-490b-a495-f1d9279cefbb', 'RECLAIMABLE', 'Dreiecksgeschäft (2er)', 'VST DEG2', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('0ef96e00-8aaf-4e13-ab53-e807b16d4a4c', '52eb0ebd-f5bf-490b-a495-f1d9279cefbb', 5);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('d8249f2b-4abc-492a-ae7a-3c3ea4d270cb', '52eb0ebd-f5bf-490b-a495-f1d9279cefbb', 10);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('5e74a464-9693-4e66-96d2-37699fa82d50', '52eb0ebd-f5bf-490b-a495-f1d9279cefbb', 13);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('24302466-4855-4171-b43f-1d49c6d1d8ed', '52eb0ebd-f5bf-490b-a495-f1d9279cefbb', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('52eb0ebd-f5bf-490b-a495-f1d9279cefbb', 'BMD', true, '11');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('52eb0ebd-f5bf-490b-a495-f1d9279cefbb', 'DVO', true, '11');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('9809d4d0-d2d0-47e0-b342-b6b65ff75582', 'RECLAIMABLE', 'Dreiecksgeschäft (3er)', 'VST DEG3', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('74b89898-a064-4b21-854e-92dea96ce7b8', '9809d4d0-d2d0-47e0-b342-b6b65ff75582', 5);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('38c129e8-c516-401b-8217-6b9c501c0bd2', '9809d4d0-d2d0-47e0-b342-b6b65ff75582', 10);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('724d2fdc-76b5-4471-a4c8-36db05f9526d', '9809d4d0-d2d0-47e0-b342-b6b65ff75582', 13);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('0a9d6bf6-c97e-42b6-85ff-06147502436b', '9809d4d0-d2d0-47e0-b342-b6b65ff75582', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('9809d4d0-d2d0-47e0-b342-b6b65ff75582', 'BMD', true, '93');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('9809d4d0-d2d0-47e0-b342-b6b65ff75582', 'DVO', true, '93');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('9809d4d0-d2d0-47e0-b342-b6b65ff75582', 'BMD', false, '92');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('9809d4d0-d2d0-47e0-b342-b6b65ff75582', 'DVO', false, '92');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, vat_id_required, country)
    values ('43136e14-4334-4ee8-bfe1-080634e631de', 'RECLAIMABLE', 'Aufwand nicht steuerbar', 'VST n.sb.', false, 'AT');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('43136e14-4334-4ee8-bfe1-080634e631de', 'BMD', true, '80');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('43136e14-4334-4ee8-bfe1-080634e631de', 'DVO', true, '80');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('fe87a34f-ec45-4c96-bbca-8154385b4cb7', 'RECLAIMABLE', 'innergemeinschaftlicher Erwerb', 'igE', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('02fa9936-d3b6-4642-802e-79e4b1ba7ad4', 'fe87a34f-ec45-4c96-bbca-8154385b4cb7', 5);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('09c89d00-3d3a-4f6f-b2c9-01c3c9d6f4f0', 'fe87a34f-ec45-4c96-bbca-8154385b4cb7', 10);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('09c89d00-3d3a-4f6f-b2c9-01c3c9d6f4f0', 'DATEV', true, '18');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('6d3ce997-ecc3-4995-b3dc-63ee25e3fadd', 'fe87a34f-ec45-4c96-bbca-8154385b4cb7', 13);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('6d3ce997-ecc3-4995-b3dc-63ee25e3fadd', 'DATEV', true, '16');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('c8a8d3f7-d464-4af3-952a-7a3539156a80', 'fe87a34f-ec45-4c96-bbca-8154385b4cb7', 20);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('c8a8d3f7-d464-4af3-952a-7a3539156a80', 'DATEV', true, '19');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('fe87a34f-ec45-4c96-bbca-8154385b4cb7', 'BMD', true, '9');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('fe87a34f-ec45-4c96-bbca-8154385b4cb7', 'DVO', true, '9');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('fe87a34f-ec45-4c96-bbca-8154385b4cb7', 'BMD', false, '8');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('fe87a34f-ec45-4c96-bbca-8154385b4cb7', 'DVO', false, '8');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('1f927787-1504-4981-b0e0-f2c9f1358632', 'RECLAIMABLE', 'innergemeinschaftlicher Erwerb', 'igE', true, true, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('7f40dae2-5657-4f88-b164-e242fcdf1c71', '1f927787-1504-4981-b0e0-f2c9f1358632', 5);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('7f40dae2-5657-4f88-b164-e242fcdf1c71', 'DATEV', true, '16');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('ba319d6d-760a-4989-8838-4b6393bcfcc8', '1f927787-1504-4981-b0e0-f2c9f1358632', 7);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('ba319d6d-760a-4989-8838-4b6393bcfcc8', 'DATEV', true, '18');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('b8b7a171-7b58-46b5-a942-30fe5cdb7675', '1f927787-1504-4981-b0e0-f2c9f1358632', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('b8b7a171-7b58-46b5-a942-30fe5cdb7675', 'DATEV', true, '17');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('aac9cec1-f80d-44e2-9d74-4ee448013762', '1f927787-1504-4981-b0e0-f2c9f1358632', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('aac9cec1-f80d-44e2-9d74-4ee448013762', 'DATEV', true, '19');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('1f927787-1504-4981-b0e0-f2c9f1358632', 'BMD', true, '9');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('1f927787-1504-4981-b0e0-f2c9f1358632', 'DVO', true, '9');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('1f927787-1504-4981-b0e0-f2c9f1358632', 'BMD', false, '8');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('1f927787-1504-4981-b0e0-f2c9f1358632', 'DVO', false, '8');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('adeefcff-5e8c-474c-8747-44b0a548ed56', 'RECLAIMABLE', 'innergemeinschaftlicher Erwerb neuer Fahrzeuge', 'igE KFZ', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('5f37bf7a-beb4-4586-9abd-6ff986df195b', 'adeefcff-5e8c-474c-8747-44b0a548ed56', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('adeefcff-5e8c-474c-8747-44b0a548ed56', 'BMD', true, '4');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('adeefcff-5e8c-474c-8747-44b0a548ed56', 'DVO', true, '4');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('03b9a185-391d-4ddc-adc6-a38867cc25c2', 'RECLAIMABLE', 'innergemeinschaftlicher Erwerb neuer Fahrzeuge', 'igE KFZ', true, true, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('84e2ed4a-543f-489a-b45b-4ddbaec319c7', '03b9a185-391d-4ddc-adc6-a38867cc25c2', 16);
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('dfaed99a-d54b-421b-bbb4-7de3c546b1ba', '03b9a185-391d-4ddc-adc6-a38867cc25c2', 19);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('03b9a185-391d-4ddc-adc6-a38867cc25c2', 'BMD', true, '35');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('03b9a185-391d-4ddc-adc6-a38867cc25c2', 'DVO', true, '35');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('dd8487dc-81e6-4654-bac5-a085d25c7d0b', 'RECLAIMABLE', 'Reverse Charge Eingang', 'A RC', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('6c0f2abc-44ef-479f-8b9b-170bfbc8d06f', 'dd8487dc-81e6-4654-bac5-a085d25c7d0b', 20);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('6c0f2abc-44ef-479f-8b9b-170bfbc8d06f', 'DATEV', true, '506');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('6c0f2abc-44ef-479f-8b9b-170bfbc8d06f', 'DATEV', false, '6506');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('dd8487dc-81e6-4654-bac5-a085d25c7d0b', 'BMD', true, '19');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('dd8487dc-81e6-4654-bac5-a085d25c7d0b', 'DVO', true, '19');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('dd8487dc-81e6-4654-bac5-a085d25c7d0b', 'BMD', false, '18');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('dd8487dc-81e6-4654-bac5-a085d25c7d0b', 'DVO', false, '18');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('3bc29b8a-daed-497a-aca0-3d4f855a50c5', 'RECLAIMABLE', 'Reverse Charge Eingang', 'A RC 13/2 Nr.1', true, true, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('1d9a53f5-dafd-4e19-ab90-8a61ee5d5f40', '3bc29b8a-daed-497a-aca0-3d4f855a50c5', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('1d9a53f5-dafd-4e19-ab90-8a61ee5d5f40', 'DATEV', true, '511');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('1d9a53f5-dafd-4e19-ab90-8a61ee5d5f40', 'DATEV', false, '6511');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('387e3c3f-5106-4a4f-aebc-16d6e32e7a43', '3bc29b8a-daed-497a-aca0-3d4f855a50c5', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('387e3c3f-5106-4a4f-aebc-16d6e32e7a43', 'DATEV', true, '511');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('387e3c3f-5106-4a4f-aebc-16d6e32e7a43', 'DATEV', false, '6511');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('3bc29b8a-daed-497a-aca0-3d4f855a50c5', 'BMD', true, '19');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('3bc29b8a-daed-497a-aca0-3d4f855a50c5', 'DVO', true, '19');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('3bc29b8a-daed-497a-aca0-3d4f855a50c5', 'BMD', false, '18');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('3bc29b8a-daed-497a-aca0-3d4f855a50c5', 'DVO', false, '18');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('e77d686e-92f2-4c96-a5c1-b7c912327e90', 'RECLAIMABLE', 'Aufwand RC Bauleistung', 'A RC 19/1a', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('c3e22b0f-28ab-4b40-8573-529fbf92f4ec', 'e77d686e-92f2-4c96-a5c1-b7c912327e90', 20);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('c3e22b0f-28ab-4b40-8573-529fbf92f4ec', 'DATEV', true, '511');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('c3e22b0f-28ab-4b40-8573-529fbf92f4ec', 'DATEV', false, '6511');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('e77d686e-92f2-4c96-a5c1-b7c912327e90', 'BMD', true, '29');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('e77d686e-92f2-4c96-a5c1-b7c912327e90', 'DVO', true, '29');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('e77d686e-92f2-4c96-a5c1-b7c912327e90', 'BMD', false, '28');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('e77d686e-92f2-4c96-a5c1-b7c912327e90', 'DVO', false, '28');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('f9232dc3-aa25-496e-b2c8-36c56f409dc8', 'RECLAIMABLE', 'Aufwand RC Bauleistung', 'A RC 13/2 Nr.4', true, true, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('9547735b-c55b-4f3d-b631-0b127f716747', 'f9232dc3-aa25-496e-b2c8-36c56f409dc8', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('9547735b-c55b-4f3d-b631-0b127f716747', 'DATEV', true, '526');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('9547735b-c55b-4f3d-b631-0b127f716747', 'DATEV', false, '6526');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('0682147c-d0a4-4666-91be-9f5c398cf5fb', 'f9232dc3-aa25-496e-b2c8-36c56f409dc8', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('0682147c-d0a4-4666-91be-9f5c398cf5fb', 'DATEV', true, '526');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('0682147c-d0a4-4666-91be-9f5c398cf5fb', 'DATEV', false, '6526');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('f9232dc3-aa25-496e-b2c8-36c56f409dc8', 'BMD', true, '29');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('f9232dc3-aa25-496e-b2c8-36c56f409dc8', 'DVO', true, '29');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('f9232dc3-aa25-496e-b2c8-36c56f409dc8', 'BMD', false, '28');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('f9232dc3-aa25-496e-b2c8-36c56f409dc8', 'DVO', false, '28');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('43ba7dd9-789c-4b6a-9f06-9c3aa5032965', 'RECLAIMABLE', 'RC KFZ §19/1', 'A RC KFZ', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('44cbdc7f-e87d-4ff8-bcc4-6e8e2c053d80', '43ba7dd9-789c-4b6a-9f06-9c3aa5032965', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('43ba7dd9-789c-4b6a-9f06-9c3aa5032965', 'BMD', true, '44');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('43ba7dd9-789c-4b6a-9f06-9c3aa5032965', 'DVO', true, '44');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('2b158ebf-f347-4da8-beb0-fe2b4dbe7769', 'RECLAIMABLE', 'RC Gebäude §19/1', 'A RC Gebäude', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('9d2d396c-c010-44b2-9d8e-ad8de107b20b', '2b158ebf-f347-4da8-beb0-fe2b4dbe7769', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('2b158ebf-f347-4da8-beb0-fe2b4dbe7769', 'BMD', true, '45');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('2b158ebf-f347-4da8-beb0-fe2b4dbe7769', 'DVO', true, '45');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('c619ebed-7503-4ce7-a023-3eefd0cd2ecb', 'RECLAIMABLE', 'RC Gebäude §19/1', 'A RC 13/2 Nr. 8', true, true, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('af93ae6b-bd66-4527-893b-e555efdcc776', 'c619ebed-7503-4ce7-a023-3eefd0cd2ecb', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('af93ae6b-bd66-4527-893b-e555efdcc776', 'DATEV', true, '551');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('af93ae6b-bd66-4527-893b-e555efdcc776', 'DATEV', false, '6551');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('f6c2d0aa-26ba-43e2-a938-dc5150ab31b3', 'c619ebed-7503-4ce7-a023-3eefd0cd2ecb', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('f6c2d0aa-26ba-43e2-a938-dc5150ab31b3', 'DATEV', true, '551');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('f6c2d0aa-26ba-43e2-a938-dc5150ab31b3', 'DATEV', false, '6551');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('aa3ea0e0-1ff4-4c13-b580-afc45eb9cc7c', 'RECLAIMABLE', 'Aufwand RC Sicherungsübereignung', 'A RC 19/1b', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('e11e1d8e-60ed-4a41-98ae-74146201c878', 'aa3ea0e0-1ff4-4c13-b580-afc45eb9cc7c', 20);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('e11e1d8e-60ed-4a41-98ae-74146201c878', 'DATEV', true, '516');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('e11e1d8e-60ed-4a41-98ae-74146201c878', 'DATEV', false, '6516');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('aa3ea0e0-1ff4-4c13-b580-afc45eb9cc7c', 'BMD', true, '23');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('aa3ea0e0-1ff4-4c13-b580-afc45eb9cc7c', 'DVO', true, '23');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('aa3ea0e0-1ff4-4c13-b580-afc45eb9cc7c', 'BMD', false, '22');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('aa3ea0e0-1ff4-4c13-b580-afc45eb9cc7c', 'DVO', false, '22');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('adacca37-9747-43fe-ac0f-2b802e2e2e94', 'RECLAIMABLE', 'Aufwand RC Sicherungsübereignung', 'A RC 13/2 Nr.2', true, true, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('7264f173-bff2-4e36-944d-f6c23f6d400a', 'adacca37-9747-43fe-ac0f-2b802e2e2e94', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('7264f173-bff2-4e36-944d-f6c23f6d400a', 'DATEV', true, '516');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('7264f173-bff2-4e36-944d-f6c23f6d400a', 'DATEV', false, '6516');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('dcad8361-6c7f-4b85-abb9-54cf3194bb42', 'adacca37-9747-43fe-ac0f-2b802e2e2e94', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('dcad8361-6c7f-4b85-abb9-54cf3194bb42', 'DATEV', true, '516');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('dcad8361-6c7f-4b85-abb9-54cf3194bb42', 'DATEV', false, '6516');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('1fcc6bb6-d26a-4082-bf92-0c22bf1bd15f', 'RECLAIMABLE', 'Aufwand RC Gas & Elektrizität', 'A RC 19/1c', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('ff976248-5482-45df-8e83-26c3a57ff0e6', '1fcc6bb6-d26a-4082-bf92-0c22bf1bd15f', 20);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('ff976248-5482-45df-8e83-26c3a57ff0e6', 'DATEV', true, '521');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('ff976248-5482-45df-8e83-26c3a57ff0e6', 'DATEV', false, '6521');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('1fcc6bb6-d26a-4082-bf92-0c22bf1bd15f', 'BMD', true, '26');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('1fcc6bb6-d26a-4082-bf92-0c22bf1bd15f', 'DVO', true, '26');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('1fcc6bb6-d26a-4082-bf92-0c22bf1bd15f', 'BMD', false, '25');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('1fcc6bb6-d26a-4082-bf92-0c22bf1bd15f', 'DVO', false, '25');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('c4ea90af-cc95-4400-9db3-bf5a5a24e78e', 'RECLAIMABLE', 'Aufwand RC Gas & Elektrizität', 'A RC 13/2 Nr.5', true, true, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('d69f707e-32eb-4a3d-8f15-bc122e0778e8', 'c4ea90af-cc95-4400-9db3-bf5a5a24e78e', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('d69f707e-32eb-4a3d-8f15-bc122e0778e8', 'DATEV', true, '531');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('d69f707e-32eb-4a3d-8f15-bc122e0778e8', 'DATEV', false, '6531');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('fb86736c-efd1-4948-ab48-02bff60ea32b', 'c4ea90af-cc95-4400-9db3-bf5a5a24e78e', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('fb86736c-efd1-4948-ab48-02bff60ea32b', 'DATEV', true, '531');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('fb86736c-efd1-4948-ab48-02bff60ea32b', 'DATEV', false, '6531');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('191f43f9-812d-44d6-9ac4-f820153fdf62', 'RECLAIMABLE', 'RC KFZ §19/1c', 'RC 19/1c KFZ', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('16c04e52-0dd3-4de1-b549-40e956e57b28', '191f43f9-812d-44d6-9ac4-f820153fdf62', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('191f43f9-812d-44d6-9ac4-f820153fdf62', 'BMD', true, '46');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('191f43f9-812d-44d6-9ac4-f820153fdf62', 'DVO', true, '46');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('aad1ef4b-7a7f-424f-90ec-c290da6bb2d4', 'RECLAIMABLE', 'RC Gebäude §19/1c', 'RC 19/1c Gebäude', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('50010999-af6b-4b6f-b8de-ec06097bbcef', 'aad1ef4b-7a7f-424f-90ec-c290da6bb2d4', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('aad1ef4b-7a7f-424f-90ec-c290da6bb2d4', 'BMD', true, '47');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('aad1ef4b-7a7f-424f-90ec-c290da6bb2d4', 'DVO', true, '47');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('7108da6d-0dd9-4925-8de2-ce2c57c1801e', 'RECLAIMABLE', 'Aufwand RC Schrott & Altmetall', 'A RC 19/1d Schrott', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('ed264575-4a73-4b05-b2c3-a2b06d25c6ce', '7108da6d-0dd9-4925-8de2-ce2c57c1801e', 20);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('ed264575-4a73-4b05-b2c3-a2b06d25c6ce', 'DATEV', true, '526');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('ed264575-4a73-4b05-b2c3-a2b06d25c6ce', 'DATEV', false, '6526');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('7108da6d-0dd9-4925-8de2-ce2c57c1801e', 'BMD', true, '59');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('7108da6d-0dd9-4925-8de2-ce2c57c1801e', 'DVO', true, '59');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('7108da6d-0dd9-4925-8de2-ce2c57c1801e', 'BMD', false, '58');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('7108da6d-0dd9-4925-8de2-ce2c57c1801e', 'DVO', false, '58');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('90425b2c-35a2-42bc-867c-6eaf17730241', 'RECLAIMABLE', 'Aufwand RC Schrott & Altmetall', 'A RC 13/2 Nr.7', true, true, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('af869a1c-029a-4a10-b1ec-fec0276e0ad6', '90425b2c-35a2-42bc-867c-6eaf17730241', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('af869a1c-029a-4a10-b1ec-fec0276e0ad6', 'DATEV', true, '546');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('af869a1c-029a-4a10-b1ec-fec0276e0ad6', 'DATEV', false, '6546');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('d3d0b309-9e1f-41f5-8720-05e7b630698b', '90425b2c-35a2-42bc-867c-6eaf17730241', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('d3d0b309-9e1f-41f5-8720-05e7b630698b', 'DATEV', true, '546');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('d3d0b309-9e1f-41f5-8720-05e7b630698b', 'DATEV', false, '6546');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('90425b2c-35a2-42bc-867c-6eaf17730241', 'BMD', true, '59');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('90425b2c-35a2-42bc-867c-6eaf17730241', 'DVO', true, '59');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('90425b2c-35a2-42bc-867c-6eaf17730241', 'BMD', false, '58');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('90425b2c-35a2-42bc-867c-6eaf17730241', 'DVO', false, '58');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('a071f63a-f8a4-4d6e-956e-4ad62ed6bcff', 'RECLAIMABLE', 'Aufwand RC Treibhausgasemissionszertifikate', 'A RC 19/1e', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('691fccd9-a613-479a-9928-7934583d04be', 'a071f63a-f8a4-4d6e-956e-4ad62ed6bcff', 20);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('691fccd9-a613-479a-9928-7934583d04be', 'DATEV', true, '531');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('691fccd9-a613-479a-9928-7934583d04be', 'DATEV', false, '6531');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('a071f63a-f8a4-4d6e-956e-4ad62ed6bcff', 'BMD', true, '89');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('a071f63a-f8a4-4d6e-956e-4ad62ed6bcff', 'DVO', true, '89');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('a071f63a-f8a4-4d6e-956e-4ad62ed6bcff', 'BMD', false, '88');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('a071f63a-f8a4-4d6e-956e-4ad62ed6bcff', 'DVO', false, '88');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('4fa1d190-9afc-400f-b121-cbbfbfbaf714', 'RECLAIMABLE', 'Aufwand RC Treibhausgasemissionszertifikate', 'A RC 13/2 Nr.6', true, true, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('395b8743-25e3-4d97-ab1a-3f767aa65345', '4fa1d190-9afc-400f-b121-cbbfbfbaf714', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('395b8743-25e3-4d97-ab1a-3f767aa65345', 'DATEV', true, '541');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('395b8743-25e3-4d97-ab1a-3f767aa65345', 'DATEV', false, '6541');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('88b7a89a-8cf3-42a7-bbd2-1a4139ddbb26', '4fa1d190-9afc-400f-b121-cbbfbfbaf714', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('88b7a89a-8cf3-42a7-bbd2-1a4139ddbb26', 'DATEV', true, '541');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('88b7a89a-8cf3-42a7-bbd2-1a4139ddbb26', 'DATEV', false, '6541');

----

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('9eda4779-98c1-478b-b3d8-a93954c8cba1', 'RECLAIMABLE', 'Aufwand RC Mobilfunk', 'A RC 13/2 Nr. 10', true, true, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('48f70454-a7e5-4d34-9f1d-1993341f96b9', '9eda4779-98c1-478b-b3d8-a93954c8cba1', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('48f70454-a7e5-4d34-9f1d-1993341f96b9', 'DATEV', true, '561');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('48f70454-a7e5-4d34-9f1d-1993341f96b9', 'DATEV', false, '6561');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('3e04bf23-83e7-4321-a2d5-5e94d47d3fca', '9eda4779-98c1-478b-b3d8-a93954c8cba1', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('3e04bf23-83e7-4321-a2d5-5e94d47d3fca', 'DATEV', true, '561');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('3e04bf23-83e7-4321-a2d5-5e94d47d3fca', 'DATEV', false, '6561');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('36dd5d36-d03b-43ec-8780-33ec0c49e52c', 'RECLAIMABLE', 'RC KFZ §19/1e', 'RC 19/1e KFZ', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('e79e9440-fe03-4e67-a6d2-05bbb7b506b7', '36dd5d36-d03b-43ec-8780-33ec0c49e52c', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('36dd5d36-d03b-43ec-8780-33ec0c49e52c', 'BMD', true, '50');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('36dd5d36-d03b-43ec-8780-33ec0c49e52c', 'DVO', true, '50');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('e6ca804a-3896-467a-9f1a-31cc6b4f71ce', 'RECLAIMABLE', 'RC Gebäude §19/1e', 'RC 19/1e Gebäude', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('486b5ad1-a1b5-4d48-8130-221732926a4d', 'e6ca804a-3896-467a-9f1a-31cc6b4f71ce', 20);
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('e6ca804a-3896-467a-9f1a-31cc6b4f71ce', 'BMD', true, '51');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('e6ca804a-3896-467a-9f1a-31cc6b4f71ce', 'DVO', true, '51');

----

-- at
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('c9515810-78e5-4401-a55b-da76431a829d', 'RECLAIMABLE', 'Aufwand sonstige Leistungen EU', 'A SL EU', true, true, 'AT');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('4cafd337-6bf6-49e7-a665-7aa1dc6a2c8c', 'c9515810-78e5-4401-a55b-da76431a829d', 20);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('4cafd337-6bf6-49e7-a665-7aa1dc6a2c8c', 'DATEV', true, '541');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('4cafd337-6bf6-49e7-a665-7aa1dc6a2c8c', 'DATEV', false, '6541');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('c9515810-78e5-4401-a55b-da76431a829d', 'BMD', true, '79');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('c9515810-78e5-4401-a55b-da76431a829d', 'DVO', true, '79');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('c9515810-78e5-4401-a55b-da76431a829d', 'BMD', false, '78');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('c9515810-78e5-4401-a55b-da76431a829d', 'DVO', false, '78');

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('728089ae-8066-4eed-8a18-dfc4333fc84d', 'RECLAIMABLE', 'Aufwand sonstige Leistungen EU', 'A SL EU', true, true, 'DE');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('7c9ee633-2842-47a2-9bbf-58114fa5a052', '728089ae-8066-4eed-8a18-dfc4333fc84d', 16);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('7c9ee633-2842-47a2-9bbf-58114fa5a052', 'DATEV', true, '506');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('7c9ee633-2842-47a2-9bbf-58114fa5a052', 'DATEV', false, '6506');
insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
    values ('8901eb27-4763-40b7-b587-abf5bcf7583b', '728089ae-8066-4eed-8a18-dfc4333fc84d', 19);
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('8901eb27-4763-40b7-b587-abf5bcf7583b', 'DATEV', true, '506');
insert into public.value_added_tax_code(value_added_tax_percentage_id, accounting_system, reclaimable, code)
    values ('8901eb27-4763-40b7-b587-abf5bcf7583b', 'DATEV', false, '6506');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('728089ae-8066-4eed-8a18-dfc4333fc84d', 'BMD', true, '79');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('728089ae-8066-4eed-8a18-dfc4333fc84d', 'DVO', true, '79');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('728089ae-8066-4eed-8a18-dfc4333fc84d', 'BMD', false, '78');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('728089ae-8066-4eed-8a18-dfc4333fc84d', 'DVO', false, '78');

----

-- de
insert into public.value_added_tax (id, "type", name, short_name, net_only_amount, vat_id_required, country)
    values ('b5d08278-858f-42fa-9616-3270d4ad81da', 'RECLAIMABLE', 'Andere Steuersätze', 'OTHER', true, false, 'DE');
insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values ('b5d08278-858f-42fa-9616-3270d4ad81da', 'DATEV', true, '49');


-- EU OSS
do $$
declare
  country_vats record;
  vat_id uuid;
  vat_perc text;
  vat_perc_id uuid;
begin
  for country_vats in (select * from json_each($j${
  "BE": [21, 12, 6],
  "BG": [20, 9],
  "DK": [25],
  "EE": [22, 13, 9],
  "FI": [25.5, 14, 10],
  "FR": [20, 10, 5.5],
  "GR": [24, 13, 6],
  "IE": [23, 13.5, 9],
  "IT": [22, 10, 5],
  "HR": [25, 13, 5],
  "LV": [21, 12, 5],
  "LT": [21, 9, 5],
  "LU": [17, 14, 8],
  "MT": [18, 7, 5],
  "NL": [21, 9],
  "PL": [23, 8, 5],
  "PT": [23, 13, 6],
  "RO": [19, 9, 5],
  "SE": [25, 12, 6],
  "SK": [23, 19, 5],
  "SI": [22, 9.5, 5],
  "ES": [21, 4],
  "CZ": [21, 12],
  "HU": [27, 18, 5],
  "CY": [19, 9, 5]
}$j$::json)) loop
    -- create value added tax
    vat_id := uuid_generate_v4();
    insert into public.value_added_tax (id, "type", name, short_name, vat_id_required, country, "default")
    values (vat_id, 'PAYABLE', 'Umsatzsteuer', 'UST', false, country_vats.key, true);

    -- set bmd code
    insert into public.value_added_tax_code(value_added_tax_id, accounting_system, reclaimable, code)
    values (vat_id, 'BMD', true, '1');

    -- create value added tax percentages
    for vat_perc in (select * from json_array_elements_text(country_vats.value)) loop
      vat_perc_id := uuid_generate_v4();
      insert into public.value_added_tax_percentage (id, value_added_tax_id, percentage)
      values (vat_perc_id, vat_id, vat_perc::float8);
    end loop;
  end loop;
end
$$;
