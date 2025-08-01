\echo
\echo '=== Client company specific tax codes ==='
\echo

-- Dobler GmbH & Co. KG Baubetreuung (6baf1351-8ee8-4bc5-84ea-d1e0d7b55a9d)
INSERT INTO public.value_added_tax_code (id, value_added_tax_id, accounting_system, reclaimable, client_company_id, code, created_at, value_added_tax_percentage_id) VALUES
  ('af6e8b85-ee17-479a-92b1-c8ca76feaefa', '649927ac-81c8-4680-89f2-0a3033f19546', 'KARTHAGO', true, '6baf1351-8ee8-4bc5-84ea-d1e0d7b55a9d', '1', '2025-04-10 09:12:37.494033+00', NULL),
  ('a82187e3-cf87-4758-a53e-1a03242f7f01', '649927ac-81c8-4680-89f2-0a3033f19546', 'KARTHAGO', false, '6baf1351-8ee8-4bc5-84ea-d1e0d7b55a9d', '1/28', '2025-04-10 09:12:37.494033+00', NULL),
  ('7cf9182b-1781-4813-ab65-59b5e9ee6305', '09d34346-aed2-4c42-a50e-a966cc50f3c3', 'KARTHAGO', true, '6baf1351-8ee8-4bc5-84ea-d1e0d7b55a9d', '4/23', '2025-04-10 09:28:01.283557+00', NULL);

-- MWW AG (f885076d-7251-4517-87d2-0c4fc9e7065d)
INSERT INTO public.value_added_tax_code (id, value_added_tax_id, accounting_system, reclaimable, client_company_id, code, created_at, value_added_tax_percentage_id) VALUES
  ('cc55bb7e-9559-4eab-9c0d-923bb6e50ebc', NULL, 'DOMUS', true, 'f885076d-7251-4517-87d2-0c4fc9e7065d', 'M16', '2024-09-12 13:53:34.26002+00', 'f1c781d4-1666-4b26-8cbb-ea9ea11d6bb9'),
  ('f9615308-97c3-4dad-80eb-1e23e4b2b9e9', NULL, 'DOMUS', true, 'f885076d-7251-4517-87d2-0c4fc9e7065d', 'V16', '2024-09-12 13:53:34.26002+00', '10ee5f80-78bc-4090-932c-6daccbd37cb0'),
  ('59ff7e1c-015f-4a85-a0ab-69441ddfaf6b', NULL, 'DOMUS', true, 'f885076d-7251-4517-87d2-0c4fc9e7065d', 'V19', '2024-09-12 13:53:34.26002+00', '09047331-e649-4f4d-a92e-ef52da04c301'),
  ('038c9903-a3b9-4346-bc54-88a3b2f06aed', NULL, 'DOMUS', true, 'f885076d-7251-4517-87d2-0c4fc9e7065d', 'M19', '2024-09-12 13:53:34.26002+00', '6f13f42b-8708-4fa9-a3be-6caa6ed3a77a'),
  ('b2c8c3ad-5c7b-452f-9e28-e27de386a252', NULL, 'DOMUS', true, 'f885076d-7251-4517-87d2-0c4fc9e7065d', 'V07', '2024-09-12 13:53:34.26002+00', '00e084f6-a852-48e9-91d1-c7738524cb80'),
  ('ee627d97-7fe3-491b-9515-8fb1d7f12061', NULL, 'DOMUS', true, 'f885076d-7251-4517-87d2-0c4fc9e7065d', 'M07', '2024-09-12 13:53:34.26002+00', '00e222f4-a3e2-4780-9f70-edb09dc9d705'),
  ('77359c01-c69d-4dbb-ade2-5ed3a71f9780', NULL, 'DOMUS', true, 'f885076d-7251-4517-87d2-0c4fc9e7065d', 'V05', '2024-09-12 13:53:34.26002+00', '819727d6-ee76-47b0-a0ff-cb7aa8c2f29e'),
  ('c9467921-14ee-44b1-94bd-ca23f4b15efe', NULL, 'DOMUS', true, 'f885076d-7251-4517-87d2-0c4fc9e7065d', 'M05', '2024-09-12 13:53:34.26002+00', '79f4dd94-1c7d-47aa-a661-5957c36320f4'),
  ('20e50be4-c797-4354-8714-1de62da740cb', NULL, 'DOMUS', true, 'a4bef51d-f4e9-427a-8f22-3c544df85488', 'M1600', '2024-09-23 13:15:52.843819+00', 'f1c781d4-1666-4b26-8cbb-ea9ea11d6bb9'),
  ('ddf56ad0-0256-4c84-ab38-5b34b9aa65f9', NULL, 'DOMUS', true, 'a4bef51d-f4e9-427a-8f22-3c544df85488', 'V1600', '2024-09-23 13:15:52.843819+00', '10ee5f80-78bc-4090-932c-6daccbd37cb0'),
  ('03dea628-983a-4f87-85e4-4498b9268449', NULL, 'DOMUS', true, 'a4bef51d-f4e9-427a-8f22-3c544df85488', 'M0700', '2024-09-23 13:15:52.843819+00', '00e222f4-a3e2-4780-9f70-edb09dc9d705'),
  ('25ee1512-057a-41f8-9d8d-69c6faff0330', NULL, 'DOMUS', true, 'a4bef51d-f4e9-427a-8f22-3c544df85488', 'V0700', '2024-09-23 13:15:52.843819+00', '00e084f6-a852-48e9-91d1-c7738524cb80'),
  ('3b345392-3756-4705-a4e7-20369091c5de', NULL, 'DOMUS', true, 'a4bef51d-f4e9-427a-8f22-3c544df85488', 'M19', '2024-09-23 13:15:52.843819+00', '6f13f42b-8708-4fa9-a3be-6caa6ed3a77a'),
  ('3765cc84-7a79-45cb-a92f-81f5223082c7', NULL, 'DOMUS', true, 'a4bef51d-f4e9-427a-8f22-3c544df85488', 'V19', '2024-09-23 13:15:52.843819+00', '09047331-e649-4f4d-a92e-ef52da04c301'),
  ('02620b6a-c365-43e5-afbb-fc89b9c921c5', NULL, 'DOMUS', true, 'a4bef51d-f4e9-427a-8f22-3c544df85488', 'V5', '2024-09-23 13:15:52.843819+00', '819727d6-ee76-47b0-a0ff-cb7aa8c2f29e'),
  ('7768cf62-5ad9-4095-9cb9-40f0e8e2f9d8', NULL, 'DOMUS', true, 'a4bef51d-f4e9-427a-8f22-3c544df85488', 'M5', '2024-09-23 13:15:52.843819+00', '79f4dd94-1c7d-47aa-a661-5957c36320f4'),
  ('d74feb10-d93d-4608-8fa7-dbe09cbccc09', NULL, 'DOMUS', true, '965db9bd-00f6-4d13-b402-f7d459c0643e', 'M19', '2024-09-23 13:16:02.600826+00', '6f13f42b-8708-4fa9-a3be-6caa6ed3a77a'),
  ('f8fa8708-70be-43a2-bbf4-78ccd2c4b7b0', NULL, 'DOMUS', true, '965db9bd-00f6-4d13-b402-f7d459c0643e', 'V19', '2024-09-23 13:16:02.600826+00', '09047331-e649-4f4d-a92e-ef52da04c301'),
  ('5dea57a3-8aba-4b2a-a5ad-c403d8eabef6', NULL, 'DOMUS', true, '965db9bd-00f6-4d13-b402-f7d459c0643e', 'M07', '2024-09-23 13:16:02.600826+00', '00e222f4-a3e2-4780-9f70-edb09dc9d705'),
  ('cc53660e-9fce-4446-9cfb-73362d73b9b3', NULL, 'DOMUS', true, '965db9bd-00f6-4d13-b402-f7d459c0643e', 'V07', '2024-09-23 13:16:02.600826+00', '00e084f6-a852-48e9-91d1-c7738524cb80'),
  ('334446ff-7779-425b-8eed-431097f8c0ec', NULL, 'DOMUS', true, '965db9bd-00f6-4d13-b402-f7d459c0643e', 'M16', '2024-09-23 13:16:02.600826+00', 'f1c781d4-1666-4b26-8cbb-ea9ea11d6bb9');

-- H.-J. Treis GmbH Immobilien Hausverwaltungen (8649347d-b04e-4e44-b9fa-9972fb322fce)
INSERT INTO public.value_added_tax_code (id, value_added_tax_id, accounting_system, reclaimable, client_company_id, code, created_at, value_added_tax_percentage_id) VALUES
  ('da66f303-1034-45a4-89c1-c8b6e46059c6', NULL, 'KARTHAGO', true, '8649347d-b04e-4e44-b9fa-9972fb322fce', '1', '2025-07-24 10:30:00.000000+02', '09047331-e649-4f4d-a92e-ef52da04c301'), -- 19% VST
  ('1bfebca9-5e54-42b2-af0d-7c2a35b7630a', NULL, 'KARTHAGO', true, '8649347d-b04e-4e44-b9fa-9972fb322fce', '2', '2025-07-24 10:30:00.000000+02', '00e084f6-a852-48e9-91d1-c7738524cb80'); -- 7% VST

-- CONFORMA Immobilien Management GmbH (19b9ce90-c7f2-4e26-adcb-7ba6a7be8a69)
INSERT INTO public.value_added_tax_code (id, value_added_tax_id, accounting_system, reclaimable, client_company_id, code, created_at, value_added_tax_percentage_id) VALUES
  ('d3f039a0-42fb-403d-b874-932a95049e6c', NULL, 'KARTHAGO', true, '19b9ce90-c7f2-4e26-adcb-7ba6a7be8a69', '1', '2025-07-24 10:05:28.339951+00', '8d3bf347-6d57-4d27-872a-b4fab68b8ce8'), -- 19% VST anteilig
  ('d72da557-5bf8-4351-870a-8704e8fd4b4e', NULL, 'KARTHAGO', true, '19b9ce90-c7f2-4e26-adcb-7ba6a7be8a69', '2', '2025-07-24 10:05:28.339951+00', 'eadd308f-0e3d-4d3d-ad65-211a82ee0562'), -- 7% VST anteilig
  ('18642dea-0a91-4132-a9e6-f77a9561fe5c', NULL, 'KARTHAGO', true, '19b9ce90-c7f2-4e26-adcb-7ba6a7be8a69', '3', '2025-07-24 10:05:28.339951+00', '09047331-e649-4f4d-a92e-ef52da04c301'); -- 19% VST
