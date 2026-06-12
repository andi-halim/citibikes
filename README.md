# Citi Bike Station Availability Forecaster

Scrapes all NYC Citi Bike stations every 2 minutes, stores data in TimescaleDB, and produces availability forecasts via Prophet.

## Table of Contents

- [Stack](#stack)
- [Local Development](#local-development)
- [Connecting to the Droplet](#connecting-to-the-droplet)
- [Docker Operations](#docker-operations)
- [Grafana Dashboard](#grafana-dashboard)
- [Database Access](#database-access)
- [Writing a Migration](#writing-a-migration)
- [Deploying Changes](#deploying-changes)

---

## Stack

| Layer | Tool |
|---|---|
| Scraper | Python 3.12, APScheduler, httpx, psycopg3, structlog |
| Database | PostgreSQL 16 + TimescaleDB (Docker) |
| Dashboard | Grafana OSS (Docker) |
| Packaging | `uv` + `pyproject.toml` |
| Deployment | DigitalOcean Droplet, Docker Compose |

---

## Local Development

Dependencies are managed with `uv`. Install them for editor tooling and running scripts locally:

```bash
git clone <repo-url>
cd citibike-scraper
uv sync
cp .env.example .env  # fill in your values
```

The full Docker stack runs on the DigitalOcean Droplet. There is no need to run it locally for routine development — the workflow is edit locally, push, and deploy. See [Deploying Changes](#deploying-changes).

To test a migration or scraper change against a real database before deploying, spin up just the database:

```bash
docker compose up -d timescaledb
DATABASE_URL=postgresql://postgres:<password>@localhost:5432/citibike uv run python scraper/scraper.py
```

---

## Connecting to the Droplet

The scraper runs 24/7 on a DigitalOcean Droplet (1 vCPU / 1 GB RAM).

```bash
ssh root@<DROPLET_IP>
```

Once on the Droplet, the project lives at `~/citibike-scraper`. The `.env` file holds production credentials and is not in version control — never overwrite it without reading it first.

### Accessing Grafana and pgAdmin remotely

Ports 3000 and 5050 are not exposed publicly. Use an SSH tunnel to forward them to your local machine:

```bash
# Grafana on localhost:3000, pgAdmin on localhost:5050
ssh -L 3000:localhost:3000 -L 5050:localhost:5050 root@<DROPLET_IP>
```

Keep the terminal open, then visit http://localhost:3000 (Grafana) and http://localhost:5050 (pgAdmin) in your browser.

---

## Docker Operations

All commands run from `~/citibike-scraper` on the Droplet (or locally from the project root). On the Droplet, prefix every `docker compose` command with `sudo`.

### View running services

```bash
docker compose ps
```

### View live scraper logs

```bash
docker compose logs -f scraper
```

Press `Ctrl+C` to stop following. To see just the last 50 lines:

```bash
docker compose logs --tail 50 scraper
```

### Restart a single service

```bash
docker compose restart scraper
docker compose restart timescaledb
docker compose restart grafana
```

### Restart the entire stack

```bash
docker compose down && docker compose up -d
```

### Stop everything (data is preserved in Docker volumes)

```bash
docker compose down
```

### Rebuild the scraper image and redeploy

Used after any code change:

```bash
docker compose up -d --build scraper
```

This rebuilds the image, stops the old container, and starts a new one. TimescaleDB and Grafana are unaffected.

---

## Grafana Dashboard

Grafana is provisioned automatically from `grafana/` — no manual setup required.

**Access:**
- Local: http://localhost:3000
- Droplet: http://`<DROPLET_IP>`:3000

**Login:** credentials are in `.env` as `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`.

The dashboard **Citi Bike Station Overview** loads automatically and includes:

| Panel | What it shows |
|---|---|
| Station Map | Current fill level for all NYC stations (green → red) |
| Station 1 Time Series | `bikes_available` + `docks_available` over time for Station 1 |
| Station 2 Time Series | Same for Station 2 (select independently) |
| Weekly Pattern | Average fill rate by hour × day-of-week for Station 1 |

Use the **Station 1** and **Station 2** dropdowns at the top to switch stations. The dashboard auto-refreshes every 2 minutes to match the scraper cadence.

### Editing the dashboard

The dashboard JSON lives at `grafana/dashboards/citibike_overview.json`. After editing in the Grafana UI, export it back to keep the file in sync: **Dashboard settings → JSON Model → copy**, or use the Grafana API.

---

## Database Access

### Connect via psql in the container

```bash
docker compose exec timescaledb psql -U $POSTGRES_USER -d citibike
```

### Connect via pgAdmin

Open http://localhost:5050 (tunnel required for Droplet — see [Connecting to the Droplet](#connecting-to-the-droplet)). Login with `PGADMIN_EMAIL` / `PGADMIN_PASSWORD` from `.env`.

---

## Writing a Migration

Schema changes are tracked as numbered SQL files and applied by `db/migrate.py`. The migration runner records applied versions in the `schema_migrations` table and skips anything already applied, so all migrations must be idempotent.

### Step 1 — Create the migration file

Name it `migrations/NNN_description.sql`, where `NNN` is the next sequential number:

```bash
# Current migrations:
# 001_initial_schema.sql
# 002_add_ebikes_available.sql
# 003_add_is_installed_last_reported.sql

touch migrations/004_your_description.sql
```

Write idempotent SQL. Always use `IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS`:

```sql
-- migrations/004_add_neighborhood_index.sql
CREATE INDEX IF NOT EXISTS idx_stations_neighborhood ON stations (neighborhood);
```

### Step 2 — Update db/schema.sql

`schema.sql` is the canonical full schema for fresh installs and must stay in sync with all applied migrations.

### Step 3 — Update scraper/scraper.py (if needed)

If the migration adds columns the scraper writes, update the `INSERT` in `poll_stations()` and its row tuple.

### Step 4 — Deploy

See [Deploying Changes](#deploying-changes) below — use the schema change workflow.

---

## Deploying Changes

### Code change only (no schema change)

```bash
# On your machine
git add <files> && git commit -m "..." && git push

# On the Droplet
git pull
sudo docker compose up -d --build scraper
```

### Schema change (new migration)

```bash
# On your machine
git add migrations/ db/schema.sql && git commit -m "..." && git push

# On the Droplet
git pull
sudo docker compose up -d --build scraper
sudo docker compose run --rm scraper uv run python db/migrate.py
```

`docker compose run --rm` spins up a one-off container using the same image and environment as the running scraper, runs the migration, and exits. The live scraper is not interrupted.
