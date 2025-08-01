
create function create_role_if_not_exists(role_name text) returns void 
language plpgsql as $$
begin
  if exists (select from pg_roles where rolname = role_name) then
    raise notice 'Role % already exists', role_name;
  else
    execute 'create role '||role_name;
  end if;
end $$;

----

-- TODO: "domonda" role is unused, drop it
DROP ROLE IF EXISTS domonda;
CREATE ROLE domonda LOGIN PASSWORD 'JjTfa3Kn2N48NRWmc6X46uQJsLa2RrZM' BYPASSRLS;

SELECT create_role_if_not_exists('domonda_anonymous');
GRANT domonda_anonymous TO domonda;

-- deprecated
SELECT create_role_if_not_exists('domonda_user');
GRANT domonda_user TO domonda;

-- work group user implementing auth principles from the work group document
SELECT create_role_if_not_exists('domonda_wg_user');

SELECT create_role_if_not_exists('domonda_api');
GRANT domonda_api TO domonda;

----

drop function create_role_if_not_exists;