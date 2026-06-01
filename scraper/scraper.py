"""
Polls the Citi Bike GBFS station_status feed every 2 minutes and writes
all station snapshots to TimescaleDB. On first run, seeds the stations table
from station_information.json.
"""

import os
import time
from datetime import datetime, timezone

import httpx
import psycopg
import structlog
from apscheduler.schedulers.blocking import BlockingScheduler

log = structlog.get_logger()

GBFS_BASE = "https://gbfs.citibikenyc.com/gbfs/en"
STATION_INFO_URL = f"{GBFS_BASE}/station_information.json"
STATION_STATUS_URL = f"{GBFS_BASE}/station_status.json"

POLL_INTERVAL_SECONDS = 120
MAX_RETRIES = 3
RETRY_BACKOFF_BASE = 2  # seconds; delay = base ** attempt


def get_db_conn() -> psycopg.Connection:
    dsn = os.environ["DATABASE_URL"]
    return psycopg.connect(dsn)


def fetch_json(client: httpx.Client, url: str) -> dict:
    for attempt in range(MAX_RETRIES):
        try:
            resp = client.get(url, timeout=10)
            resp.raise_for_status()
            return resp.json()
        except Exception as exc:
            if attempt == MAX_RETRIES - 1:
                raise
            delay = RETRY_BACKOFF_BASE ** attempt
            log.warning("fetch_failed", url=url, attempt=attempt, delay=delay, error=str(exc))
            time.sleep(delay)


def seed_stations(conn: psycopg.Connection, client: httpx.Client) -> None:
    data = fetch_json(client, STATION_INFO_URL)
    stations = data["data"]["stations"]
    with conn.cursor() as cur:
        cur.executemany(
            """
            INSERT INTO stations (station_id, name, lat, lon, capacity)
            VALUES (%(station_id)s, %(name)s, %(lat)s, %(lon)s, %(capacity)s)
            ON CONFLICT (station_id) DO UPDATE
                SET name     = EXCLUDED.name,
                    lat      = EXCLUDED.lat,
                    lon      = EXCLUDED.lon,
                    capacity = EXCLUDED.capacity
            """,
            [
                {
                    "station_id": s["station_id"],
                    "name": s["name"],
                    "lat": s["lat"],
                    "lon": s["lon"],
                    "capacity": s.get("capacity", 0),
                }
                for s in stations
            ],
        )
    conn.commit()
    log.info("stations_seeded", count=len(stations))


def stations_table_empty(conn: psycopg.Connection) -> bool:
    with conn.cursor() as cur:
        cur.execute("SELECT NOT EXISTS (SELECT 1 FROM stations LIMIT 1)")
        return cur.fetchone()[0]


def poll_stations(conn: psycopg.Connection, client: httpx.Client) -> None:
    polled_at = datetime.now(timezone.utc)
    data = fetch_json(client, STATION_STATUS_URL)
    statuses = data["data"]["stations"]

    rows = [
        (
            polled_at,
            s["station_id"],
            s.get("num_bikes_available"),
            s.get("num_docks_available"),
            s.get("num_bikes_disabled"),
            s.get("num_docks_disabled"),
            s.get("is_renting") == 1,
            s.get("is_returning") == 1,
        )
        for s in statuses
    ]

    with conn.cursor() as cur:
        cur.executemany(
            """
            INSERT INTO station_snapshots
                (time, station_id, bikes_available, docks_available,
                 bikes_disabled, docks_disabled, is_renting, is_returning)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            rows,
        )
    conn.commit()
    log.info("poll_complete", snapshot_time=polled_at.isoformat(), stations=len(rows))


def run_poll() -> None:
    with httpx.Client() as client, get_db_conn() as conn:
        if stations_table_empty(conn):
            log.info("seeding_stations")
            seed_stations(conn, client)
        poll_stations(conn, client)


def main() -> None:
    log.info("scraper_starting", interval_seconds=POLL_INTERVAL_SECONDS)

    # Run once immediately so we don't wait 2 minutes on first start
    run_poll()

    scheduler = BlockingScheduler()
    scheduler.add_job(run_poll, "interval", seconds=POLL_INTERVAL_SECONDS)
    try:
        scheduler.start()
    except KeyboardInterrupt:
        log.info("scraper_stopped")


if __name__ == "__main__":
    main()
