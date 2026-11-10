-- This migration adds a new column last_seen_at to the stations table to track when a station was last seen.
ALTER TABLE stations ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;