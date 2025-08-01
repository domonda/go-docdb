-- Document sharing and commenting

insert into object.class (name) values ('ShareDocument');
insert into object.class (name) values ('ShareDocumentMention');


-------------------------------------------------------------------------------
-- iDWELL real-estate object

insert into object.class (name) values ('RealEstateObject');

insert into object.class_prop (
    "id",
    "class_name",
    "name",
    "type",
    "required",
    "options",
    "description",
    "pos"
) values (
    '0f370879-6d5a-414a-8ce8-539e7b57361e', -- id
    'RealEstateObject', -- class_name
    'Objekttyp', -- name
    'TEXT_OPTION', -- type
    true, -- required
    '{"WEG","HI","SUB","KREIS","MANDANT","MRG"}', -- options
    null, -- description
    0 -- pos
), (
    '9c68765c-a2bc-423b-be8a-28dcd5a7f39e', -- id
    'RealEstateObject', -- class_name
    'Objektnummer', -- name
    'ACCOUNT_NO', -- type
    true, -- required
    null, -- options
    null, -- description
    1 -- pos
), (
    'd83b8d10-c2d4-4226-834c-f7c8192e56d8', -- id
    'RealEstateObject', -- class_name
    'Kreis', -- name
    'ACCOUNT_NO', -- type
    false, -- required
    null, -- options
    null, -- description
    2 -- pos
), (
    '2109fc07-0043-41a1-b577-b7a227e5b929', -- id
    'RealEstateObject', -- class_name
    'Mandant', -- name
    'ACCOUNT_NO', -- type
    false, -- required
    null, -- options
    null, -- description
    3 -- pos
), (
    '75d03690-3208-49d7-9a5c-62963da90bd9', -- id
    'RealEstateObject', -- class_name
    'Anmerkungen', -- name
    'TEXT', -- type
    false, -- required
    null, -- options
    null, -- description
    4 -- pos
), (
    'ad9a9051-9df6-4a65-9804-d5c77cc2ec23', -- id
    'RealEstateObject', -- class_name
    'Straßenadresse', -- name
    'TEXT', -- type
    true, -- required
    null, -- options
    null, -- description
    5 -- pos
), (
    '1020a852-326b-4602-ba5f-5abf677f3a7a', -- id
    'RealEstateObject', -- class_name
    'Alternative Straßenadressen', -- name
    'TEXT_ARRAY', -- type
    false, -- required
    null, -- options
    null, -- description
    6 -- pos
), (
    '4e9a587a-a77c-4867-8cd5-be97e4881f9b', -- id
    'RealEstateObject', -- class_name
    'Postleitzahl', -- name
    'TEXT', -- type
    false, -- required
    null, -- options
    null, -- description
    7 -- pos
), (
    '142d2d10-688f-4650-83eb-8daf352ef631', -- id
    'RealEstateObject', -- class_name
    'Ort', -- name
    'TEXT', -- type
    false, -- required
    null, -- options
    null, -- description
    8 -- pos
), (
    '5625ef60-5dc5-4330-8c90-1f205b0b0cee', -- id
    'RealEstateObject', -- class_name
    'Land', -- name
    'COUNTRY', -- type
    true, -- required
    null, -- options
    null, -- description
    9 -- pos
), (
    'd1666e2d-9e92-4c3b-bb67-e2c3f6cc8823', -- id
    'RealEstateObject', -- class_name
    'IBAN', -- name
    'IBAN', -- type
    false, -- required
    null, -- options
    null, -- description
    10 -- pos
), (
    '26158194-9c16-40a0-91cc-6c22bf295de1', -- id
    'RealEstateObject', -- class_name
    'BIC', -- name
    'BIC', -- type
    false, -- required
    null, -- options
    null, -- description
    11 -- pos
), (
    '79063815-dac0-44bd-a0fb-59a2dd7efdf6', -- id
    'RealEstateObject', -- class_name
    'Bankverbindungen', -- name
    'BANK_ACCOUNT_ARRAY', -- type
    false, -- required
    null, -- options
    null, -- description
    12 -- pos
);


-------------------------------------------------------------------------------
-- Signa company

insert into object.class ("name") values ('SignaCompany');

insert into object.class_prop (
    "name",
    "id",
    "class_name",
    "type",
    "required",
    "options",
    "description",
    "pos"
) values (
    'SignaID', -- name
    '9e9a0b54-5fce-44be-9c70-377a5909a475', -- id
    'SignaCompany', -- class_name
    'TEXT', -- type
    true, -- required
    null, -- options
    'ID im Signa-System', -- description
    0 -- pos
), (
    'Firmenname', -- name
    '64028473-63bd-4335-a870-20c269eb14ef', -- id
    'SignaCompany', -- class_name
    'TEXT', -- type
    true, -- required
    null, -- options
    null, -- description
    10 -- pos
), (
    'UID Nummer', -- name
    '1914cbe5-94ae-4f52-a43d-163ad63cafbc', -- id
    'SignaCompany', -- class_name
    'VAT_ID', -- type
    false, -- required
    null, -- options
    null, -- description
    20 -- pos
), (
    'Email', -- name
    'e53fccd8-b672-43b7-bb13-26662d5c43b9', -- id
    'SignaCompany', -- class_name
    'EMAIL_ADDRESS', -- type
    false, -- required
    null, -- options
    null, -- description
    30 -- pos
), (
    'Straßenadresse', -- name
    'f76ac6c3-679b-4af4-8291-aa901bde2e32', -- id
    'SignaCompany', -- class_name
    'TEXT', -- type
    true, -- required
    null, -- options
    null, -- description
    40 -- pos
), (
    'Andere Namen und Adressen', -- name
    'f5b23927-2a07-4132-ae8f-411a7c92ed94', -- id
    'SignaCompany', -- class_name
    'TEXT_ARRAY', -- type
    false, -- required
    null, -- options
    null, -- description
    50 -- pos
), (
    'Postleitzahl', -- name
    'aa6a50d1-a768-4213-af81-a8e501028c5f', -- id
    'SignaCompany', -- class_name
    'TEXT', -- type
    true, -- required
    null, -- options
    null, -- description
    60 -- pos
), (
    'Ort', -- name
    '4eb7483b-2f48-4e77-9d2f-9163de4f2793', -- id
    'SignaCompany', -- class_name
    'TEXT', -- type
    true, -- required
    null, -- options
    null, -- description
    70 -- pos
), (
    'Land', -- name
    'cbfc7400-1597-4204-a8fd-b58137e633df', -- id
    'SignaCompany', -- class_name
    'COUNTRY', -- type
    true, -- required
    null, -- options
    null, -- description
    80 -- pos
), (
    'BUHA-Format', -- name
    '7f3c69e6-3187-4bed-8331-fe8d136b17af', -- id
    'SignaCompany', -- class_name
    'TEXT_OPTION', -- type
    true, -- required
    '{"SAP","DATEV","Email"}', -- options
    null, -- description
    90 -- pos
), (
    'Prüfer', -- name
    '0fc9e168-0610-4cec-a4d0-ec0697ba2022', -- id
    'SignaCompany', -- class_name
    'EMAIL_ADDRESS_ARRAY', -- type
    false, -- required
    null, -- options
    null, -- description
    100 -- pos
), (
    'Prüfer 2', -- name
    'ed7fd1ba-5e14-47f9-aabe-b67725b03b4f', -- id
    'SignaCompany', -- class_name
    'EMAIL_ADDRESS_ARRAY', -- type
    false, -- required
    null, -- options
    null, -- description
    110 -- pos
), (
    'Freigeber', -- name
    '0c01543d-b1e9-44c8-a8f2-a7a6e6639006', -- id
    'SignaCompany', -- class_name
    'EMAIL_ADDRESS_ARRAY', -- type
    false, -- required
    null, -- options
    'Vorstandsebene', -- description
    120 -- pos
), (
    'Freigeber 2', -- name
    'a0fa0525-cec6-49c7-a598-1f8be051aec7', -- id
    'SignaCompany', -- class_name
    'EMAIL_ADDRESS_ARRAY', -- type
    false, -- required
    null, -- options
    'Insolvenzverwalter', -- description
    130 -- pos
), (
    'Clearingstelle', -- name
    '8704900f-398f-402a-95a1-47a6aefe7a5a', -- id
    'SignaCompany', -- class_name
    'EMAIL_ADDRESS_ARRAY', -- type
    false, -- required
    null, -- options
    null, -- description
    140 -- pos
), (
    'Buchhalter', -- name
    '89682218-319a-479e-9c4b-7c030e2460cc', -- id
    'SignaCompany', -- class_name
    'EMAIL_ADDRESS_ARRAY', -- type
    false, -- required
    null, -- options
    null, -- description
    150 -- pos
), (
    'Einsichtsberechtigte', -- name
    '85c8f79c-e181-48f2-9678-394049c5e6af', -- id
    'SignaCompany', -- class_name
    'EMAIL_ADDRESS_ARRAY', -- type
    false, -- required
    null, -- options
    null, -- description
    160 -- pos
), (
    'Ablehnung Emailliste', -- name
    'a5233100-420e-4802-ac48-5771f2228c92', -- id
    'SignaCompany', -- class_name
    'EMAIL_ADDRESS_ARRAY', -- type
    false, -- required
    null, -- options
    null, -- description
    170 -- pos
);
