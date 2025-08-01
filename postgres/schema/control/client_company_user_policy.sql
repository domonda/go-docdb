CREATE POLICY client_company_user_select_policy ON control.client_company_user FOR SELECT
    TO domonda_user
    USING (
        private.current_user_super()
        or client_company_user.role_name <> 'VERIFIER'
        -- allows exposing the client company user for the current user itself
        -- NOTE: using "(select private.current_user_id())" instead fails with "infinite recursion detected"
        or client_company_user.user_id = private.current_user_id()

        -- TODO: test this implementation --
        -- EXISTS (
        --     SELECT 1 FROM control.client_company_user AS ccu
        --         INNER JOIN public.user AS u ON ((u.id = ccu.user_id) AND (u.auth0_user_id = current_setting('jwt.claims.sub')::text))
        --     WHERE (
        --         ccu.client_company_id = client_company_user.client_company_id
        --     )
        -- )
    );

----

CREATE POLICY client_company_user_insert_policy ON control.client_company_user FOR INSERT
    TO domonda_user
    WITH CHECK (
        private.current_user_super()
        or (
            (
                client_company_user.role_name <> 'VERIFIER'
            ) AND (
                EXISTS (
                    SELECT 1 FROM control.client_company_user AS ccu
                        INNER JOIN control.client_company_user_role AS ccur ON (ccur.name = ccu.role_name)
                    WHERE (
                        ccu.user_id = (SELECT id FROM private.current_user())
                    ) AND (
                        ccu.client_company_id = client_company_user.client_company_id
                    ) AND (
                        public.get_client_company_status(ccu.client_company_id) = 'DEMO' OR
                        ccur.update_users = true
                    )
                )
            )
        )
    );

----

CREATE POLICY client_company_user_update_policy ON control.client_company_user FOR UPDATE
    TO domonda_user
    USING (true) -- always true, update policy should be implemented in WITH CHECK
    WITH CHECK (
        private.current_user_super()
        or (
            (
                client_company_user.role_name <> 'VERIFIER'
            ) AND (
                EXISTS (
                    SELECT 1 FROM control.client_company_user AS ccu
                        INNER JOIN control.client_company_user_role AS ccur ON (ccur.name = ccu.role_name)
                    WHERE (
                        ccu.user_id = (SELECT id FROM private.current_user())
                    ) AND (
                        ccu.client_company_id = client_company_user.client_company_id
                    ) AND (
                        public.get_client_company_status(ccu.client_company_id) = 'DEMO' OR
                        ccur.update_users = true
                    )
                )
            )
        )
    );

----

CREATE POLICY client_company_user_delete_policy ON control.client_company_user FOR DELETE
    TO domonda_user
    USING (
        private.current_user_super()
        or (
            (
                client_company_user.role_name <> 'VERIFIER'
            ) AND (
                EXISTS (
                    SELECT 1 FROM control.client_company_user AS ccu
                        INNER JOIN control.client_company_user_role AS ccur ON (ccur.name = ccu.role_name)
                    WHERE (
                        ccu.user_id = (SELECT id FROM private.current_user())
                    ) AND (
                        ccu.client_company_id = client_company_user.client_company_id
                    ) AND (
                        public.get_client_company_status(ccu.client_company_id) = 'DEMO' OR
                        ccur.update_users = true
                    )
                )
            )
        )
    );

----

ALTER TABLE control.client_company_user ENABLE ROW LEVEL SECURITY;
