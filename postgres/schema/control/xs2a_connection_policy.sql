CREATE POLICY xs2a_connection_policy ON xs2a."connection" FOR ALL
    TO domonda_user
    USING (
        EXISTS (SELECT 1 FROM xs2a.bank_user WHERE id = bank_user_id)
    );

----

ALTER TABLE xs2a."connection" ENABLE ROW LEVEL SECURITY;
