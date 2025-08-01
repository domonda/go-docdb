INSERT INTO public.payment_package(
    client_company_id,
    invoice_price,
    user_price,
    accountant_user_price
) VALUES (
    'ddbc44c1-b9d9-4ada-a870-ac3566388708',
    0.35,
    10.0,
    25.0
), (
    'a4b188a1-311a-44f7-b1db-7e8c914d9274',
    0.35,
    10.0,
    25.0
), (
    '78fcff96-0100-49ab-a673-f7d6fc126746',
    0.29,
    10.0,
    10.0
), (
    '0db90bd4-6487-4a83-bc2d-ce8a85875ee1',
    0.29,
    10.0,
    10.0
), (
    '8e9323bd-8ac4-47f4-bc20-46a92d40f6f3',
    0.29,
    10.0,
    10.0
), (
    'ec31a9b5-f7fc-493c-b837-eefb0607160b',
    0.35,
    10.0,
    10.0
), (
    '14bca28f-e9fe-410d-8b76-59c7b897829f',
    0.35,
    10.0,
    25.0
), (
    '92237723-4f8c-4b44-888d-a4a57d2a37ea',
    0.35,
    10.0,
    25.0
), (
    'c1fd6da0-e1e5-4607-bc92-885339a37649',
    0.35,
    10.0,
    25.0
), (
    '4241813e-19c6-4024-98e1-1d9d9ef46cb4',
    0.34,
    10.0,
    0.0
), (
    'f82659cd-d436-45ee-8db5-2e69b1ab83d2',
    0.35,
    10.0,
    25.0
), (
    'fd8b9c2a-5cf7-49e4-9395-a70623d44ce5',
    0.35,
    10.0,
    25.0
);

CREATE FUNCTION insert_packages_for_missing_accounting_companies() RETURNS void AS $func$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT ac.client_company_id FROM public.accounting_company ac
            WHERE NOT EXISTS (SELECT 1 FROM public.payment_package p WHERE p.client_company_id = ac.client_company_id)
    LOOP
        INSERT INTO public.payment_package(client_company_id, invoice_price, user_price, accountant_user_price)
            VALUES(rec.client_company_id, 0.35, 10.0, 25.0);
    END LOOP;
END
$func$ LANGUAGE plpgsql VOLATILE;

SELECT insert_packages_for_missing_accounting_companies();

INSERT INTO public.payment_package(
    client_company_id,
    price,
    invoice_price,
    user_price,
    invoices_included,
    users_included
) VALUES (
    '1622b9dc-15f3-4932-a122-e2c185d5cd46',
    240.0,
    0.5,
    10.0,
    500,
    8
), (
    '1bcd15c4-df7e-4274-894c-5c5d5923f531',
    220.0,
    0.5,
    10.0,
    350,
    4
), (
    'b401e9d3-5dee-47a9-a34b-27845b86b5e7',
    49.0,
    0.5,
    10.0,
    100,
    2
), (
    'b2884374-d052-4858-b3c6-b1eb33e39e49',
    49.0,
    0.5,
    10.0,
    100,
    2
), (
    '6433b7af-6b01-4050-966d-343a84879425',
    220.0,
    0.5,
    10.0,
    500,
    3
), (
    '4f1a15c7-64e6-43d2-b214-66663754fa53',
    49.0,
    0.5,
    10.0,
    100,
    2
), (
    '32009891-aea0-4248-a837-d653a459b4ee',
    49.0,
    0.5,
    10.0,
    100,
    2
), (
    '86441375-2b59-45f5-bb99-308515939260',
    89.0,
    0.5,
    10.0,
    200,
    2
), (
    '4a1b4d7f-ba73-4805-a737-4f5fd4b6adfe',
    89.0,
    0.5,
    10.0,
    200,
    3
), (
    '39e6d34b-d95f-4e67-89c2-342fc5a15772',
    49.0,
    0.5,
    10.0,
    100,
    2
), (
    'b026a4f6-714a-41bf-9682-d1cc53c55cc1',
    49.0,
    0.5,
    10.0,
    100,
    2
), (
    '2f35c8d2-8627-4b1f-90e6-96db26434d42',
    180.0,
    0.5,
    10.0,
    250,
    15
); 

INSERT INTO public.payment_package(
    client_company_id,
    price,
    invoice_price,
    user_price,
    invoices_included
) VALUES (
    '6fd1e0ce-7db4-4545-b025-752b235aace9',
    99.0,
    0.5,
    10.0,
    150
), (
    '5008cbfd-3ff9-445f-a561-45780b0b1ef9',
    99.0,
    0.5,
    10.0,
    150
);

INSERT INTO public.payment_package (
    client_company_id,
    invoice_price,
    user_price
) VALUES (
    '7effb73c-6a94-4773-9bc5-516062f4cbd5',
    0.5,
    10.0
), (
    '1fd71fc8-d8d8-4b1b-91f0-7928d996d331',
    0.5,
    10.0
), (
    'f912d276-87b5-4c63-b81c-96faac2f837f',
    0.75,
    10.0
), (
    '3d99550b-11da-429f-9df3-e4c9c0bd57c1',
    0.5,
    10.0
), (
    '31d406e0-a538-4bb7-bffd-3ea9b1a083da',
    0.4,
    8.0
), (
    'd296e68b-c48e-4d60-a5d8-0ba11f88048e',
    0.4,
    8.0
), (
    'd01f94ec-23be-48d1-8a1c-26f1b76ea2af',
    0.5,
    10.0
), (
    '4a7e8386-c2b9-4ada-b8fc-c587865fd1d0',
    0.5,
    10.0
), (
    '8d5af743-b151-4a1d-a0b9-e3c5cfdb7f25',
    0.5,
    10.0
), (
    'bcba681d-c2b9-4c3b-9d4d-67603988bb35',
    0.5,
    10.0
), (
    'cf0fd4f4-1e2a-4c45-a6a3-079b60c1d27e',
    0.5,
    10.0
), (
    '76bd3f8a-5b37-4a6b-a3d1-7787b8e54686',
    0.50,
    10.0
);