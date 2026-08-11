\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS vectorscale CASCADE;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vectorscale') OR
     NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector') THEN
    RAISE EXCEPTION 'vectorscale and vector extensions must both be installed';
  END IF;
END
$$;
