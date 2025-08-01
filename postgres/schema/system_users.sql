insert into public.user
    (id,                                     client_company_id,                      "type",   first_name,             "language")
values
	-- WARNING: 'Unknown' is a special user that is used as replacement for unknown normal users,
	-- it does not have the special system user permissions
    ('08a34dc4-6e9a-4d61-b395-d123005e65d3', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Unknown',              'en'), -- MUST be inserted first
    ('cbc843af-4745-4754-bfaf-f6d0b9b27f9d', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Recover',              'en'),
    ('db3e9596-0ca2-4db7-9fb3-e0db6f03faab', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Cleanup',              'en'),
    ('d59e5071-3f08-4091-b5a9-bb9da199f688', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Buchhaltungssystem',   'en'), -- SyncWithAbacus
    ('979f0d19-f247-4763-8b5f-1fceded2a34b', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Fastbill',             'en'),
    ('c8ee802b-7605-4095-87b7-d5db56c7b0af', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Billomat',             'en'),
    ('68c539ac-c89c-456e-baf3-92082ed452a6', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Rechnungsextraktion',  'en'), -- SyncWithBluDelta
    ('6e4156e5-faff-4656-a2f2-f4d0dfc36fff', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'GetMyInvoices',        'en'),
    ('f7afb279-d9ea-46d5-a09a-7d3c067fc91a', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Testing',              'en'),
    ('b2e0ed5c-b25a-4fee-854f-a33a4bc682f6', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'API',                  'en'),
    ('bde919f0-3e23-4bfa-81f1-abff4f45fb51', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Rule',                 'en'),
    ('273a2e53-80ed-4ac5-803b-34a21691acf6', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Automator',            'en'),
    ('88eca1ff-c10e-46ea-a643-55325f4520cf', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Collector',            'en'),
    ('23c53c85-9712-4317-b920-2277823b8988', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Compass',              'en'),
    ('52e1c2db-fc50-431b-89bf-7858da09a2a3', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'VatSearch',            'en'),
    ('a77649b5-ff6d-4e87-a17c-23df3b2cad71', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Accounting Suggester', 'en'),
    ('d1149988-b146-4ff6-984f-a0a76f5355fa', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Externe Email',        'en'),
    ('ec1152e5-be64-4d8e-93a6-3f3ebe6fd4e7', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Automated Matching',   'en'),
    ('8fba3dc6-2b1c-45bc-8c0d-ecd967c412f9', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Cloning',              'en'),
    ('08ba4950-baae-42f3-9df0-80effdd29f79', '7acda277-f07c-4975-bd12-d23deace6a9a', 'SYSTEM', 'Signa',                'de'); -- For Signa customer project
