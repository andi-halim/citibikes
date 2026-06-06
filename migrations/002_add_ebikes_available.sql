-- Add ebikes_available to station_snapshots to differentiate e-bike vs classic bike counts.
-- Historical rows predate this column so they are cleared; collection restarts clean.

TRUNCATE TABLE station_snapshots;

ALTER TABLE station_snapshots
    ADD COLUMN IF NOT EXISTS ebikes_available INT;
