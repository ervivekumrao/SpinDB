# SpinDB

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Engine](https://img.shields.io/badge/Engine-Podman_%7C_Docker-orange.svg)](#prerequisites--automatic-pre-flight-check)
[![Author](https://img.shields.io/badge/Author-Vivek_Umrao-green.svg)](https://github.com/vivekumrao)

> **SPDX-License-Identifier:** Apache-2.0  
> **Copyright:** (c) 2024-2026 Vivek Umrao and SpinDB contributors.

A fast, unified developer CLI (`spinctl`) for spinning up containerized databases, in-memory caches, and lakehouse engines using
**Podman** (default, secure, rootless) with automatic fallback to **Docker**.

---

## Quickstart

Run `bin/spinctl` from the repository root (or add `bin/` to your `$PATH`):

```bash
# Spin up PostgreSQL on port 5432
./bin/spinctl -t postgres -p 5432 -n dev-pg

# Spin up Redis cache on port 6379
./bin/spinctl -t redis -p 6379 -n dev-redis

# Spin up MySQL on port 3306 with persistent host storage
./bin/spinctl -t mysql -p 3306 -n dev-mysql -d /data/mysql
```

---

## Prerequisites & Automatic Pre-Flight Check

You do **not** need to manually check dependencies. When you run `./bin/spinctl`, the script automatically checks your
host system:

- **Default Engine:** Uses **Podman** (rootless and daemonless).
- **Fallback Engine:** If Podman is missing or unprivileged user namespaces are unavailable, it notifies you and seamlessly uses **Docker**.
- **Missing Tools:** If any tool or container engine is missing, the script displays the **exact copy-paste install
  command** for your specific operating system (Ubuntu/Debian, Fedora/RHEL, Arch, Alpine, macOS, WSL).

To run the pre-flight check without launching a database:

```bash
./bin/spinctl --preflight
```

---

## Supported Databases & Engines

| Option (`-t`) | Engine                                                 | Default Port    | Internal Data Path          |
|:--------------|:-------------------------------------------------------|:----------------|:----------------------------|
| `mysql`       | MySQL Community Server                                 | `3306`          | `/var/lib/mysql`            |
| `mariadb`     | MariaDB Server                                         | `3306`          | `/var/lib/mysql`            |
| `postgres`    | PostgreSQL                                             | `5432`          | `/var/lib/postgresql/data`  |
| `pgvector`    | PostgreSQL with pgvector AI Vector Embeddings           | `5432`          | `/var/lib/postgresql/data`  |
| `mssql`       | Microsoft SQL Server (2022)                            | `1433`          | `/var/opt/mssql`            |
| `oracle`      | Oracle Autonomous Database Free                        | `1521`          | `/opt/oracle/oradata`       |
| `db2`         | IBM DB2 Community Edition                              | `50000`         | `/database`                 |
| `mongodb`     | MongoDB Document Database                              | `27017`         | `/data/db`                  |
| `redis`       | Redis / Valkey Cache & Key-Value                       | `6379`          | `/data`                     |
| `clickhouse`  | ClickHouse Columnar Analytics (OLAP)                   | `8123` / `9000` | `/var/lib/clickhouse`       |
| `cockroach`   | CockroachDB Distributed SQL (Web UI: 8080)             | `26257`         | `/cockroach/cockroach-data` |
| `snowflake`   | Snowflake Local Emulator (DuckDB-backed)               | `8080`          | `/data`                     |
| `databricks`  | Databricks Local Engine (Spark + Delta Lake, UI: 4040) | `10000`         | `/opt/spark/data`           |

---

## CLI Options Reference

```bash
./bin/spinctl [OPTIONS]
```

| Option | Long Option               | Description                                              | Default                               |
|:-------|:--------------------------|:---------------------------------------------------------|:--------------------------------------|
| `-t`   | `--database-type`         | Database vendor name (e.g. `mysql`, `postgres`, `redis`) | `mysql`                               |
| `-p`   | `--docker-port`, `--port` | Host port to map to the database                         | Auto-allocated free sequential port  |
| `-b`   | `--bind`, `--host-ip`     | Host IP to bind container ports                          | `127.0.0.1` (Localhost security)     |
|        | `--bind-all`              | Bind to `0.0.0.0` (all interfaces, for external network) | Disabled                              |
| `-n`   | `--database-name`         | Container instance name                                  | `<engine>-<port>` (e.g. `mysql-3306`)|
| `-v`   | `--database-version`      | Container image tag/version                              | `latest` (or `2022-latest` for MSSQL) |
|        | `--versions`, `--list-versions` | List available database image versions for engine       | -                                     |
| `-d`   | `--data-dir`, `--volume`  | Host directory or named volume for persistent storage    | Ephemeral container storage           |
| `-m`   | `--memory`                | Memory limit (e.g. `512m`, `2g`)                         | Unbounded                             |
|        | `--cpus`                  | CPU limit (e.g. `1.5`, `2.0`)                            | Unbounded                             |
| `-f`   | `--force`                 | Force recreate container if name already exists          | False                                 |
|        | `--rebuild`               | Force image build instead of fast runtime launch         | False                                 |
| `-e`   | `--engine`                | Force container runtime (`podman` or `docker`)           | Auto-detected                         |
| `-c`   | `--check`, `--preflight`  | Run environment checkup only                             | -                                     |
| `-h`   | `--help`                  | Display usage instructions                               | -                                     |

---

## Managing Containers

Control database containers without remembering engine-specific syntax:

```bash
# View all SpinDB containers (or specific container)
./bin/spinctl status [name]

# Start a stopped database container
./bin/spinctl start <name>

# Restart running container
./bin/spinctl restart <name>

# Follow container log output
./bin/spinctl logs <name>

# Launch interactive database client shell directly inside container
./bin/spinctl connect <name>

# Export connection strings & environment variables (.env format)
./bin/spinctl env <name>

# Stop container (or pass --all to stop all)
./bin/spinctl stop [name|--all]

# Remove container (or pass --all to remove all)
./bin/spinctl rm [name|--all]
```

---

## Database Version Discovery & Multi-Variant Provisioning

### 1. Discovering Available Database Image Versions
SpinDB provides a unified version catalog across all 13 supported engines. It combines **locally downloaded container images**, a **curated offline-first catalog** of verified LTS and stable releases, and **TTL-governed registry discovery**:

```bash
# List all 13 supported database engines and their recommended versions:
./bin/spinctl versions

# Inspect complete version catalog & sub-versions for PostgreSQL:
./bin/spinctl versions postgres

# Filter for a specific sub-version (e.g. 16.1):
./bin/spinctl versions postgres 16.1

# Bypass the 24h cache and force-refresh tags from the registry:
./bin/spinctl versions postgres --refresh

# Offline-only mode (executes purely from local disk cache & curated catalog):
./bin/spinctl versions postgres --offline
```

* **12–24h Cache TTL**: Remote version metadata is cached at `~/.cache/spindb/versions/<engine>.cache` for 24 hours (configurable via `SPINDB_CACHE_TTL` or `Database.properties`). Queries execute locally in < 5ms without unnecessary network calls.

### 2. Spinning Multiple Variants of the Same Database Concurrently
You can run multiple major and minor variants of the same database simultaneously. SpinDB automatically isolates host ports and assigns collision-free, descriptive container names in the format `<engine>-<version>-<port>`:

```bash
# Spin up PostgreSQL 14 (Port 5432) -> Container Name: postgres-14-5432
./bin/spinctl -t postgres -v 14

# Spin up PostgreSQL 15 (Auto-allocated Port 5433) -> Container Name: postgres-15-5433
./bin/spinctl -t postgres -v 15

# Spin up PostgreSQL 16.1 (Auto-allocated Port 5434) -> Container Name: postgres-16.1-5434
./bin/spinctl -t postgres -v 16.1

# Spin up PostgreSQL 17 (Auto-allocated Port 5435) -> Container Name: postgres-17-5435
./bin/spinctl -t postgres -v 17
```

View all running variants side-by-side:
```bash
./bin/spinctl status
```

---

## Configuration & Credentials

Default database names, usernames, passwords, and reference JDBC connection strings are defined
in [Database.properties](Database.properties).

To customize credentials locally without modifying version-controlled files:

```bash
# Create local override (gitignored by default)
cp config/database.env.example Database.properties.local
```

---

## In-Depth Documentation

For advanced architecture, developer guides, security policies, and testing manuals, refer to the `docs/` directory:

- 📘 **[Architecture & Blueprint](docs/ARCHITECTURE.md)** — Modular subsystems, container lifecycles, and storage design.
- 🗄️ **[Database Engine Reference](docs/DATABASE_GUIDE.md)** — Connection strings (JDBC, Python, Node.js), client CLI
  commands, and schemas for all 12 engines.
- 🛡️ **[Security & Hardening Policy](docs/SECURITY.md)** — Rootless containers, privilege mitigation, and credential
  governance.
- 🧪 **[In-Depth Testing Manual](docs/TESTING.md)** — Test harness, unit tests, static linting, and CI/CD integration.

---

## Developer Automation (`Makefile`)

```bash
make preflight    # Check host tools and container engines
make lint         # Run static syntax and license checks
make test         # Run full test suite (lint + unit + integration)
make status       # Show running database instances
make clean        # Clean temporary build artifacts
```

---

## Author & Maintainer

- **Lead Developer:** **Vivek Umrao**
- **Repository & Contributions:** SpinDB Contributors

---

## License

```
SPDX-License-Identifier: Apache-2.0
Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
```

Licensed under the **Apache License, Version 2.0**. See the [LICENSE](LICENSE) file for complete terms and permissions.
