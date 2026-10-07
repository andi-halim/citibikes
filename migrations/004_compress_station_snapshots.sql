-- This migration compresses the station_snapshots hypertable and adds a compression policy to automatically compress chunks older than 7 days.
ALTER TABLE station_snapshots SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'station_id',
  timescaledb.compress_orderby   = 'time DESC'
);
SELECT add_compression_policy('station_snapshots', INTERVAL '7 days', if_not_exists => true);

-- Compress existing chunks one at a time so each one frees its space before the next
-- One-off compression is meant to be run manually in psql
-- SELECT format('SELECT compress_chunk(%L, if_not_compressed => true);', c)
-- FROM show_chunks('station_snapshots', older_than => INTERVAL '7 days') c \gexec

-- SELECT pg_size_pretty(hypertable_size('station_snapshots'));