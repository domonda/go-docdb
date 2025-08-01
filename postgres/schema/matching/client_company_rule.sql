CREATE TABLE matching.client_company_rule (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    client_company_id uuid REFERENCES public.client_company(company_id) ON DELETE CASCADE,

    created_at created_time NOT NULL
);

GRANT SELECT ON matching.client_company_rule TO domonda_user;

COMMENT ON TABLE matching.client_company_rule IS '@name matchingClientCompanyRule';

CREATE UNIQUE INDEX client_company_rule_client_company_id_key ON matching.client_company_rule (COALESCE(client_company_id, '00000000-0000-0000-0000-000000000000'));

----

CREATE TABLE matching.client_company_rule_check (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    rule_id  uuid NOT NULL REFERENCES matching.client_company_rule(id) ON DELETE CASCADE,
    check_id uuid NOT NULL REFERENCES matching.check(id) ON DELETE RESTRICT, -- NOTE: first delete rules, then checks
    UNIQUE(rule_id, check_id),

    priority float8 NOT NULL CHECK (priority > 0),
    UNIQUE(rule_id, priority),

    enabled boolean NOT NULL DEFAULT true,

    created_at created_time NOT NULL
);

GRANT SELECT ON matching.client_company_rule_check TO domonda_user;

COMMENT ON TABLE matching.client_company_rule_check IS '@name matchingClientCompanyRuleCheck';

CREATE INDEX client_company_rule_check_rule_id ON matching.client_company_rule_check (rule_id);
CREATE INDEX client_company_rule_check_check_id ON matching.client_company_rule_check (check_id);
CREATE INDEX client_company_rule_check_priority ON matching.client_company_rule_check (priority);
CREATE INDEX client_company_rule_check_enabled ON matching.client_company_rule_check (enabled);

----

CREATE FUNCTION public.client_company_disabled_matching_checks(
	client_company public.client_company
) RETURNS SETOF matching.check AS $$
    SELECT * FROM matching.check
    WHERE id = any(client_company.skip_matching_check_ids)
    ORDER BY array_position(client_company.skip_matching_check_ids, id)
$$ LANGUAGE SQL STABLE;

----

CREATE FUNCTION matching.filter_matching_checks(
    client_company_id uuid = null,
    search_text text = null
) RETURNS SETOF matching.check AS $$
    SELECT c FROM matching.check AS c
        INNER JOIN (
            matching.client_company_rule_check AS ccrc
            INNER JOIN matching.client_company_rule AS ccr ON ccr.id = ccrc.rule_id
        ) ON ccrc.check_id = c.id
    WHERE ccrc.enabled
    AND (
        CASE (EXISTS (SELECT 1 FROM matching.client_company_rule WHERE client_company_rule.client_company_id = filter_matching_checks.client_company_id))
            WHEN true THEN ccr.client_company_id = filter_matching_checks.client_company_id
            ELSE ccr.client_company_id IS NULL
        END
    ) AND (
        filter_matching_checks.search_text IS NULL
        OR c.name ILIKE '%' || filter_matching_checks.search_text || '%'
    )
    ORDER BY ccrc.priority DESC
$$ LANGUAGE SQL STABLE;
