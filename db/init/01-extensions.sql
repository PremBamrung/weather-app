-- Enable extensions in the single weather database.
-- timescaledb is already in shared_preload_libraries on the -ha image.
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS vector;        -- pgvector, for later vector-search work
-- CREATE EXTENSION IF NOT EXISTS vectorscale; -- pgvectorscale (DiskANN), enable if/when needed
-- CREATE EXTENSION IF NOT EXISTS postgis;     -- geospatial, enable if/when needed
