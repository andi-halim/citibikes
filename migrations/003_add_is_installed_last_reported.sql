-- Add is_installed and last_reported to station_snapshots for station health tracking

ALTER TABLE station_snapshots
    ADD COLUMN IF NOT EXISTS is_installed   BOOLEAN;

ALTER TABLE station_snapshots
    ADD COLUMN IF NOT EXISTS last_reported  TIMESTAMPTZ;
