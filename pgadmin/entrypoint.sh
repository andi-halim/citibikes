#!/bin/sh
# Build servers.json from env vars so the TimescaleDB server is pre-registered.
# pgAdmin has no volume, so it imports this file on every container start.
cat > /tmp/servers.json <<EOF
{
  "Servers": {
    "1": {
      "Name": "citibike",
      "Group": "Servers",
      "Host": "timescaledb",
      "Port": 5432,
      "MaintenanceDB": "${POSTGRES_DB}",
      "Username": "${POSTGRES_USER}",
      "SSLMode": "prefer"
    }
  }
}
EOF

exec /entrypoint.sh "$@"
