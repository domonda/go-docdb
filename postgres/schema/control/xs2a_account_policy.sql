CREATE POLICY xs2a_account_policy ON xs2a.account FOR ALL
    TO domonda_user
    USING (
        EXISTS (SELECT 1 FROM xs2a.bank_user WHERE id = bank_user_id)
    );

----

ALTER TABLE xs2a.account ENABLE ROW LEVEL SECURITY;
