-- Run this as the target PostgreSQL superuser after restoring
-- gitlabhq_production.  amcheck is required by current GitLab releases and
-- was not installed in the PostgreSQL 17 source database.
CREATE EXTENSION IF NOT EXISTS amcheck;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS plpgsql;
