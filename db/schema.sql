-- Migration tracking (must exist before anything else)
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ DEFAULT NOW()
);

-- Static station metadata, seeded once from GBFS station_information feed
CREATE TABLE IF NOT EXISTS stations (
    station_id   TEXT PRIMARY KEY,
    name         TEXT        NOT NULL,
    lat          DOUBLE PRECISION NOT NULL,
    lon          DOUBLE PRECISION NOT NULL,
    capacity     INT         NOT NULL,
    neighborhood TEXT
);

-- Time-series table: one row per station per 2-minute poll
-- TimescaleDB hypertable partitioned by time
CREATE TABLE IF NOT EXISTS station_snapshots (
    time             TIMESTAMPTZ NOT NULL,
    station_id       TEXT        NOT NULL,
    bikes_available  INT,
    ebikes_available INT,
    docks_available  INT,
    bikes_disabled   INT,
    docks_disabled   INT,
    is_renting       BOOLEAN,
    is_returning     BOOLEAN,
    is_installed     BOOLEAN,
    last_reported    TIMESTAMPTZ
);
SELECT create_hypertable('station_snapshots', 'time', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS idx_snapshots_station_time
    ON station_snapshots (station_id, time DESC);

-- Compress chunks older than 7 days (segmented per station for fast per-station queries)
ALTER TABLE station_snapshots SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'station_id',
    timescaledb.compress_orderby   = 'time DESC'
);
SELECT add_compression_policy('station_snapshots', INTERVAL '7 days', if_not_exists => true);

-- Hourly weather observations for NYC (lat ~40.73, lon ~-73.93)
CREATE TABLE IF NOT EXISTS weather_observations (
    time         TIMESTAMPTZ PRIMARY KEY,
    temp_f       REAL,
    precip_in    REAL,
    wind_mph     REAL,
    weather_code INT
);

-- Forecast outputs written after each nightly model run
CREATE TABLE IF NOT EXISTS station_forecasts (
    generated_at    TIMESTAMPTZ NOT NULL,
    forecast_time   TIMESTAMPTZ NOT NULL,
    station_id      TEXT        NOT NULL,
    predicted_bikes REAL,
    lower_bound     REAL,
    upper_bound     REAL,
    PRIMARY KEY (generated_at, forecast_time, station_id)
);
