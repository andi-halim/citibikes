-- Data verification tests for Phase 1
-- Run after scraper has been active for at least a few minutes

\echo '=== TEST 1: stations table seeded ==='
SELECT
    COUNT(*)            AS total_stations,
    COUNT(neighborhood) AS with_neighborhood
FROM stations;

\echo ''
\echo '=== TEST 2: snapshots collected ==='
SELECT
    COUNT(*)                            AS total_rows,
    COUNT(DISTINCT station_id)          AS unique_stations,
    MIN(time)                           AS first_snapshot,
    MAX(time)                           AS latest_snapshot,
    ROUND(EXTRACT(EPOCH FROM (MAX(time) - MIN(time))) / 60, 1) AS span_minutes
FROM station_snapshots;

\echo ''
\echo '=== TEST 3: poll cadence (gap between snapshots should be ~2 min) ==='
SELECT
    ROUND(AVG(gap_seconds)::numeric, 1) AS avg_gap_seconds,
    ROUND(MIN(gap_seconds)::numeric, 1) AS min_gap_seconds,
    ROUND(MAX(gap_seconds)::numeric, 1) AS max_gap_seconds
FROM (
    SELECT
        EXTRACT(EPOCH FROM (time - LAG(time) OVER (ORDER BY time))) AS gap_seconds
    FROM (
        SELECT DISTINCT time FROM station_snapshots ORDER BY time
    ) t
) gaps
WHERE gap_seconds IS NOT NULL;

\echo ''
\echo '=== TEST 4: sample of 5 recent snapshots ==='
SELECT
    s.time,
    st.name,
    s.bikes_available,
    s.docks_available,
    ROUND(s.bikes_available::numeric / NULLIF(st.capacity, 0) * 100, 1) AS fill_pct
FROM station_snapshots s
JOIN stations st USING (station_id)
ORDER BY s.time DESC
LIMIT 5;

\echo ''
\echo '=== TEST 5: no nulls in critical columns ==='
SELECT
    COUNT(*) FILTER (WHERE station_id IS NULL) AS null_station_id,
    COUNT(*) FILTER (WHERE time IS NULL)       AS null_time,
    COUNT(*) FILTER (WHERE bikes_available IS NULL) AS null_bikes,
    COUNT(*) FILTER (WHERE docks_available IS NULL) AS null_docks
FROM station_snapshots;
