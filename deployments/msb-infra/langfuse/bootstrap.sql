-- Dedicated role + database for Langfuse on the SHARED infra-postgres.
-- Run once, as the postgres superuser:
--   msb exec infra -- docker exec -i infra-postgres \
--     psql -U postgres -v pw="'<LANGFUSE_DB_PASSWORD>'" -f - < bootstrap.sql
-- Langfuse owns only its own database; it gets no rights over any other tenant.

\set ON_ERROR_STOP on

CREATE ROLE langfuse LOGIN PASSWORD :pw;
CREATE DATABASE langfuse OWNER langfuse;
REVOKE ALL ON DATABASE langfuse FROM PUBLIC;
GRANT CONNECT ON DATABASE langfuse TO langfuse;
