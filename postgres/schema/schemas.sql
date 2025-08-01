-- public
-- SCHEMA PUBLIC EXISTS
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO domonda;
GRANT USAGE ON SCHEMA public TO domonda_user;
GRANT USAGE ON SCHEMA public TO domonda_wg_user;

-- private
CREATE SCHEMA IF NOT EXISTS private;
GRANT USAGE ON SCHEMA private TO domonda_user;
GRANT USAGE ON SCHEMA private TO domonda_wg_user;

-- docdb
CREATE SCHEMA IF NOT EXISTS docdb;
GRANT USAGE ON SCHEMA docdb TO domonda_user;
GRANT USAGE ON SCHEMA docdb TO domonda_wg_user;

-- worker
CREATE SCHEMA IF NOT EXISTS worker;
GRANT USAGE ON SCHEMA worker TO domonda_user;
-- GRANT USAGE ON SCHEMA worker TO domonda_wg_user; TODO: necessary?

-- object
CREATE SCHEMA IF NOT EXISTS object;
GRANT USAGE ON SCHEMA object TO domonda_user;
GRANT USAGE ON SCHEMA object TO domonda_wg_user;

-- work
CREATE SCHEMA IF NOT EXISTS work;
GRANT USAGE ON SCHEMA work TO domonda_user;
GRANT USAGE ON SCHEMA work TO domonda_wg_user;

-- control
CREATE SCHEMA IF NOT EXISTS control;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA control TO domonda;
GRANT USAGE ON SCHEMA control TO domonda_user;
GRANT USAGE ON SCHEMA control TO domonda_wg_user; -- TODO: necessary ONLY for prod env, why?

-- api
CREATE SCHEMA IF NOT EXISTS api;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA api TO domonda;
GRANT USAGE ON SCHEMA api TO domonda_api;

-- xs2a
CREATE SCHEMA IF NOT EXISTS xs2a;
GRANT USAGE ON SCHEMA xs2a TO domonda_user;
GRANT USAGE ON SCHEMA xs2a TO domonda_wg_user;

-- rule
CREATE SCHEMA IF NOT EXISTS rule;
GRANT USAGE ON SCHEMA rule TO domonda_user;
GRANT USAGE ON SCHEMA rule TO domonda_wg_user;

-- automation
CREATE SCHEMA IF NOT EXISTS automation;
GRANT USAGE ON SCHEMA automation TO domonda_user;
GRANT USAGE ON SCHEMA automation TO domonda_wg_user;

-- matching
CREATE SCHEMA IF NOT EXISTS matching;
GRANT USAGE ON SCHEMA matching TO domonda_user;
GRANT USAGE ON SCHEMA matching TO domonda_wg_user;

-- builder
CREATE SCHEMA IF NOT EXISTS builder;
GRANT USAGE ON SCHEMA builder TO domonda_user;
GRANT USAGE ON SCHEMA builder TO domonda_wg_user;

-- super
CREATE SCHEMA IF NOT EXISTS super;

-- monitor
CREATE SCHEMA IF NOT EXISTS monitor;

-- sync
CREATE SCHEMA IF NOT EXISTS sync;

-- extensions
\ir extensions.sql
