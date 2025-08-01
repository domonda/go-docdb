create type api.jwt_token as (
    aud text, -- must be `postgraphql`
    sub text, -- company_id
    exp int   -- expiry timestamp
);

----

create function api.current_client_company_id()
returns uuid as
$$
begin
    return current_setting('jwt.claims.sub')::uuid;
exception when others then
    return null;
end
$$
language plpgsql stable cost 100000;

comment on function api.current_client_company_id is 'Currently authenticated `ClientCompany.company_id`.';
