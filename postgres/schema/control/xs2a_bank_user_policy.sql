CREATE POLICY xs2a_bank_user_policy ON xs2a.bank_user FOR ALL
    TO domonda_user
    USING (
        (SELECT id = user_id FROM private.current_user())
    );

----

ALTER TABLE xs2a.bank_user ENABLE ROW LEVEL SECURITY;
