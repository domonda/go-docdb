-- TODO: implement with row level security

CREATE VIEW api.user WITH (security_barrier) AS
    SELECT
        u.id,
        u.client_company_id,
        u.email,
        u.title,
        u.first_name,
        u.last_name,
        u.updated_at,
        u.created_at
    FROM public.user AS u
        INNER JOIN api.client_company cc ON (cc.company_id = u.client_company_id);

GRANT SELECT ON TABLE api.user TO domonda_api;

COMMENT ON COLUMN api.user.email IS '@notNull';
COMMENT ON COLUMN api.user.first_name IS '@notNull';
COMMENT ON COLUMN api.user.client_company_id IS '@notNull';
COMMENT ON VIEW api.user IS $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
A domonda `User`.$$;

create function api.user_full_name("user" api.user)
returns text as $$
    select trim(coalesce("user".title || ' ', '') || coalesce("user".first_name || ' ', '') || coalesce("user".last_name, ''))
$$ language sql stable;
comment on function api.user_full_name is '@notNull';
