#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
"""
SpinDB Web Studio - Modern Browser-Based SQL Client & Database Management Studio.
Zero external dependencies (uses Python standard library).
"""

import csv
import io
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http import HTTPStatus
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

# Paths
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
PROPERTIES_FILE = PROJECT_ROOT / "Database.properties"
LOCAL_PROPERTIES_FILE = PROJECT_ROOT / "Database.properties.local"
LIB_DIR = PROJECT_ROOT / "lib"
DRIVERS_DIR = PROJECT_ROOT / "drivers"
USER_CACHE_DRIVERS_DIR = Path.home() / ".cache" / "spindb" / "drivers"
SPINCTL_BIN = PROJECT_ROOT / "bin" / "spinctl"

# Supported Driver Catalog with official Maven and portal download locations
DRIVER_CATALOG = {
    "postgres": {
        "engine": "postgres",
        "displayName": "PostgreSQL",
        "driverClass": "org.postgresql.Driver",
        "fileName": "postgresql-42.7.3.jar",
        "version": "42.7.3",
        "mavenCoords": "org.postgresql:postgresql:42.7.3",
        "downloadUrl": "https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.3/postgresql-42.7.3.jar",
        "portalUrl": "https://jdbc.postgresql.org/download/",
        "defaultPort": 5432,
        "defaultDb": "pgdb",
        "defaultUser": "userid",
        "defaultUrlTemplate": "jdbc:postgresql://HOST:PORT/DBNAME",
    },
    "pgvector": {
        "engine": "pgvector",
        "displayName": "PostgreSQL (pgvector)",
        "driverClass": "org.postgresql.Driver",
        "fileName": "postgresql-42.7.3.jar",
        "version": "42.7.3",
        "mavenCoords": "org.postgresql:postgresql:42.7.3",
        "downloadUrl": "https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.3/postgresql-42.7.3.jar",
        "portalUrl": "https://jdbc.postgresql.org/download/",
        "defaultPort": 5432,
        "defaultDb": "vectordb",
        "defaultUser": "userid",
        "defaultUrlTemplate": "jdbc:postgresql://HOST:PORT/DBNAME",
    },
    "mysql": {
        "engine": "mysql",
        "displayName": "MySQL",
        "driverClass": "com.mysql.cj.jdbc.Driver",
        "fileName": "mysql-connector-j-8.4.0.jar",
        "version": "8.4.0",
        "mavenCoords": "com.mysql:mysql-connector-j:8.4.0",
        "downloadUrl": "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.4.0/mysql-connector-j-8.4.0.jar",
        "portalUrl": "https://dev.mysql.com/downloads/connector/j/",
        "defaultPort": 3306,
        "defaultDb": "userdata",
        "defaultUser": "userid",
        "defaultUrlTemplate": "jdbc:mysql://HOST:PORT/DBNAME?allowPublicKeyRetrieval=true&useSSL=false",
    },
    "mariadb": {
        "engine": "mariadb",
        "displayName": "MariaDB",
        "driverClass": "org.mariadb.jdbc.Driver",
        "fileName": "mariadb-java-client-3.4.0.jar",
        "version": "3.4.0",
        "mavenCoords": "org.mariadb.jdbc:mariadb-java-client:3.4.0",
        "downloadUrl": "https://repo1.maven.org/maven2/org/mariadb/jdbc/mariadb-java-client/3.4.0/mariadb-java-client-3.4.0.jar",
        "portalUrl": "https://mariadb.com/downloads/connectors/connectors-data-access/java-connector/",
        "defaultPort": 3306,
        "defaultDb": "userdata",
        "defaultUser": "userid",
        "defaultUrlTemplate": "jdbc:mariadb://HOST:PORT/DBNAME",
    },
    "mssql": {
        "engine": "mssql",
        "displayName": "Microsoft SQL Server",
        "driverClass": "com.microsoft.sqlserver.jdbc.SQLServerDriver",
        "fileName": "mssql-jdbc-12.6.2.jre11.jar",
        "version": "12.6.2",
        "mavenCoords": "com.microsoft.sqlserver:mssql-jdbc:12.6.2.jre11",
        "downloadUrl": "https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/12.6.2.jre11/mssql-jdbc-12.6.2.jre11.jar",
        "portalUrl": "https://learn.microsoft.com/en-us/sql/connect/jdbc/download-microsoft-jdbc-driver-for-sql-server",
        "defaultPort": 1433,
        "defaultDb": "mssql",
        "defaultUser": "sa",
        "defaultUrlTemplate": "jdbc:sqlserver://HOST:PORT;databaseName=DBNAME;selectMethod=cursor;sendStringParametersAsUnicode=false;datetimeParameterType=datetime;trustServerCertificate=true;",
    },
    "oracle": {
        "engine": "oracle",
        "displayName": "Oracle Database Free",
        "driverClass": "oracle.jdbc.OracleDriver",
        "fileName": "ojdbc11-23.4.0.24.05.jar",
        "version": "23.4.0.24.05",
        "mavenCoords": "com.oracle.database.jdbc:ojdbc11:23.4.0.24.05",
        "downloadUrl": "https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc11/23.4.0.24.05/ojdbc11-23.4.0.24.05.jar",
        "portalUrl": "https://www.oracle.com/database/technologies/appdev/jdbc-downloads.html",
        "defaultPort": 1521,
        "defaultDb": "oracledb",
        "defaultUser": "userid",
        "defaultUrlTemplate": "jdbc:oracle:thin:@//HOST:PORT/DBNAME",
    },
    "db2": {
        "engine": "db2",
        "displayName": "IBM DB2",
        "driverClass": "com.ibm.db2.jcc.DB2Driver",
        "fileName": "jcc-11.5.9.0.jar",
        "version": "11.5.9.0",
        "mavenCoords": "com.ibm.db2:jcc:11.5.9.0",
        "downloadUrl": "https://repo1.maven.org/maven2/com/ibm/db2/jcc/11.5.9.0/jcc-11.5.9.0.jar",
        "portalUrl": "https://www.ibm.com/support/pages/db2-jdbc-driver-versions-and-downloads",
        "defaultPort": 50000,
        "defaultDb": "ibmdb",
        "defaultUser": "userid",
        "defaultUrlTemplate": "jdbc:db2://HOST:PORT/DBNAME",
    },
    "clickhouse": {
        "engine": "clickhouse",
        "displayName": "ClickHouse Analytics",
        "driverClass": "com.clickhouse.jdbc.ClickHouseDriver",
        "fileName": "clickhouse-jdbc-0.6.3-all.jar",
        "version": "0.6.3",
        "mavenCoords": "com.clickhouse:clickhouse-jdbc:0.6.3:all",
        "downloadUrl": "https://repo1.maven.org/maven2/com/clickhouse/clickhouse-jdbc/0.6.3/clickhouse-jdbc-0.6.3-all.jar",
        "portalUrl": "https://github.com/ClickHouse/clickhouse-java/releases",
        "defaultPort": 8123,
        "defaultDb": "userdata",
        "defaultUser": "userid",
        "defaultUrlTemplate": "jdbc:ch://HOST:PORT/DBNAME",
    },
    "cockroach": {
        "engine": "cockroach",
        "displayName": "CockroachDB Distributed SQL",
        "driverClass": "org.postgresql.Driver",
        "fileName": "postgresql-42.7.3.jar",
        "version": "42.7.3",
        "mavenCoords": "org.postgresql:postgresql:42.7.3",
        "downloadUrl": "https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.3/postgresql-42.7.3.jar",
        "portalUrl": "https://jdbc.postgresql.org/download/",
        "defaultPort": 26257,
        "defaultDb": "userdata",
        "defaultUser": "userid",
        "defaultUrlTemplate": "jdbc:postgresql://HOST:PORT/DBNAME?sslmode=disable",
    },
    "mongodb": {
        "engine": "mongodb",
        "displayName": "MongoDB NoSQL Document",
        "driverClass": "mongodb.jdbc.MongoDriver",
        "fileName": "mongodb-jdbc-5.0.0.jar",
        "version": "5.0.0",
        "mavenCoords": "org.mongodb:mongodb-jdbc:5.0.0",
        "downloadUrl": "https://repo1.maven.org/maven2/org/mongodb/mongodb-jdbc/5.0.0/mongodb-jdbc-5.0.0.jar",
        "portalUrl": "https://github.com/mongodb/mongo-jdbc-driver/releases",
        "defaultPort": 27017,
        "defaultDb": "mgdb",
        "defaultUser": "userid",
        "defaultUrlTemplate": "jdbc:mongodb://USER_ID:USER_PASSWORD@HOST:PORT/DBNAME?authSource=admin",
    },
    "snowflake": {
        "engine": "snowflake",
        "displayName": "Snowflake Emulator (DuckDB)",
        "driverClass": "net.snowflake.client.jdbc.SnowflakeDriver",
        "fileName": "snowflake-jdbc-3.16.0.jar",
        "version": "3.16.0",
        "mavenCoords": "net.snowflake:snowflake-jdbc:3.16.0",
        "downloadUrl": "https://repo1.maven.org/maven2/net/snowflake/snowflake-jdbc/3.16.0/snowflake-jdbc-3.16.0.jar",
        "portalUrl": "https://developers.snowflake.com/drivers/jdbc/",
        "defaultPort": 8080,
        "defaultDb": "USERDATA",
        "defaultUser": "userid",
        "defaultUrlTemplate": "jdbc:snowflake://HOST:PORT/?db=DBNAME&schema=PUBLIC&warehouse=COMPUTE_WH&ssl=off",
    },
    "databricks": {
        "engine": "databricks",
        "displayName": "Databricks Spark & Delta",
        "driverClass": "org.apache.hive.jdbc.HiveDriver",
        "fileName": "hive-jdbc-3.1.3-standalone.jar",
        "version": "3.1.3",
        "mavenCoords": "org.apache.hive:hive-jdbc:3.1.3:standalone",
        "downloadUrl": "https://repo1.maven.org/maven2/org/apache/hive/hive-jdbc/3.1.3/hive-jdbc-3.1.3-standalone.jar",
        "portalUrl": "https://www.databricks.com/spark/jdbc-drivers-download",
        "defaultPort": 10000,
        "defaultDb": "userdata",
        "defaultUser": "userid",
        "defaultUrlTemplate": "jdbc:hive2://HOST:PORT/DBNAME;auth=noSasl",
    },
    "redis": {
        "engine": "redis",
        "displayName": "Redis / Valkey Cache",
        "driverClass": "redis.clients.jedis.UnifiedJedis",
        "fileName": "jedis-5.1.2.jar",
        "version": "5.1.2",
        "mavenCoords": "redis.clients:jedis:5.1.2",
        "downloadUrl": "https://repo1.maven.org/maven2/redis/clients/jedis/5.1.2/jedis-5.1.2.jar",
        "portalUrl": "https://github.com/redis/jedis",
        "defaultPort": 6379,
        "defaultDb": "0",
        "defaultUser": "default",
        "defaultUrlTemplate": "redis://:USER_PASSWORD@HOST:PORT/0",
    },
}


def load_properties():
    """Loads default configuration from Database.properties and Database.properties.local."""
    props = {}
    for pfile in [PROPERTIES_FILE, LOCAL_PROPERTIES_FILE]:
        if pfile.exists():
            with open(pfile, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if "=" in line:
                        k, v = line.split("=", 1)
                        props[k.strip()] = v.strip()
    return props


def resolve_container_engine(forced=None):
    """Detects available container runtime (Podman or Docker)."""
    if forced in ("podman", "docker"):
        return forced
    for engine in ["podman", "docker"]:
        cmd = [engine, "info"]
        try:
            res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
            if res.returncode == 0:
                return engine
        except Exception:
            continue
    # Fallback to which
    if shutil.which("docker"):
        return "docker"
    if shutil.which("podman"):
        return "podman"
    return "docker"


def get_running_containers(engine=None):
    """Discovers all SpinDB containers and general database containers across available runtimes."""
    containers = []
    seen_ids = set()
    props = load_properties()

    runtimes = [engine] if engine in ("docker", "podman") else ["docker", "podman"]

    for runtime in runtimes:
        if not shutil.which(runtime):
            continue
        cmd = [runtime, "ps", "-a", "--format", "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Labels}}"]
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5)
            if res.returncode != 0:
                continue
            lines = res.stdout.strip().split("\n")

            for line in lines:
                if not line.strip():
                    continue
                parts = line.split("\t")
                cid = parts[0].strip() if len(parts) > 0 else ""
                if cid in seen_ids:
                    continue
                seen_ids.add(cid)
                cname = parts[1].strip() if len(parts) > 1 else ""
                cimage = parts[2].strip() if len(parts) > 2 else ""
                cstatus = parts[3].strip() if len(parts) > 3 else ""
                cports = parts[4].strip() if len(parts) > 4 else ""
                clabels = parts[5].strip() if len(parts) > 5 else ""

                is_spindb = "app=spindb" in clabels or "spindb" in cname.lower() or "spindb" in clabels

                # Extract engine
                engine_type = ""
                engine_match = re.search(r"spindb\.engine=([a-zA-Z0-9_-]+)", clabels)
                if engine_match:
                    engine_type = engine_match.group(1).lower()
                else:
                    for k in DRIVER_CATALOG:
                        if k in cname.lower() or k in cimage.lower():
                            engine_type = k
                            break

                if not engine_type:
                    if not is_spindb:
                        continue
                    engine_type = "postgres"

                # Normalize engine
                if engine_type in ("postgresql",):
                    engine_type = "postgres"
                elif engine_type in ("valkey",):
                    engine_type = "redis"

                # Parse host port
                host_port = ""
                port_match = re.search(r"(?:0\.0\.0\.0|127\.0\.0\.1|:::):(\d+)->", cports)
                if port_match:
                    host_port = port_match.group(1)
                else:
                    try:
                        pcmd = [runtime, "port", cname]
                        pres = subprocess.run(pcmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=2)
                        if pres.returncode == 0 and pres.stdout:
                            pm = re.search(r":(\d+)$", pres.stdout.strip().split("\n")[0])
                            if pm:
                                host_port = pm.group(1)
                    except Exception:
                        pass

                default_catalog = DRIVER_CATALOG.get(engine_type, DRIVER_CATALOG["postgres"])
                if not host_port:
                    host_port = str(default_catalog.get("defaultPort", 5432))

                # Database name & credentials
                prefix = engine_type.upper()
                if engine_type == "postgres":
                    prefix = "POSTGRES"
                elif engine_type == "mariadb":
                    prefix = "MARIADB"
                elif engine_type == "clickhouse":
                    prefix = "CLICKHOUSE"
                elif engine_type == "mssql":
                    prefix = "MSSQL"

                dbname = props.get(f"{prefix}_DBNAME", default_catalog.get("defaultDb", "userdata"))
                user = props.get(f"{prefix}_USER_ID", default_catalog.get("defaultUser", "userid"))
                password = props.get(f"{prefix}_USER_PASSWORD", props.get(f"{prefix}_USER_PASS", "P@55w0rd"))
                if engine_type == "mssql" and user == "sa":
                    password = props.get("MSSQL_SA_PASSWORD", password)

                # Driver class & JDBC URL
                driver_class = props.get(f"{prefix}_DRIVER_CLASS", default_catalog["driverClass"])
                url_tmpl = props.get(f"{prefix}_JDBC_URL", default_catalog["defaultUrlTemplate"])
                jdbc_url = (
                    url_tmpl.replace("HOST", "127.0.0.1")
                    .replace("PORT", host_port)
                    .replace("DBNAME", dbname)
                    .replace("USER_ID", user)
                    .replace("USER_PASSWORD", password)
                    .replace("SCHEMA", "PUBLIC")
                )

                is_running = "Up" in cstatus or "running" in cstatus.lower()

                containers.append({
                    "id": cid,
                    "name": cname,
                    "engine": engine_type,
                    "runtime": runtime,
                    "displayName": default_catalog.get("displayName", engine_type.capitalize()),
                    "image": cimage,
                    "status": cstatus,
                    "isRunning": is_running,
                    "host": "127.0.0.1",
                    "port": host_port,
                    "database": dbname,
                    "user": user,
                    "password": password,
                    "driverClass": driver_class,
                    "jdbcUrl": jdbc_url,
                    "isSpinDB": is_spindb,
                })
        except Exception as e:
            sys.stderr.write(f"[WARN] Error discovering containers on {runtime}: {e}\n")

    return containers


def check_driver_downloaded(file_name):
    """Checks if a driver JAR exists in the local drivers directory, user cache, or lib fallback."""
    if not file_name:
        return False
    for dpath in [DRIVERS_DIR / file_name, USER_CACHE_DRIVERS_DIR / file_name, LIB_DIR / file_name]:
        if dpath.is_file() and dpath.stat().st_size > 1024:
            return True
    return False


def execute_database_query(engine_name, container_name, query, db_info=None):
    """Executes a query inside the container via engine-native client."""
    container_engine = (db_info.get("runtime") if db_info else None) or resolve_container_engine()
    start_time = time.time()

    query = query.strip()
    if not query:
        return {"status": "error", "message": "Empty query provided."}

    # Ensure container is running
    inspect_cmd = [container_engine, "inspect", "-f", "{{.State.Running}}", container_name]
    try:
        chk = subprocess.run(inspect_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=3)
        if "true" not in chk.stdout.lower():
            return {
                "status": "error",
                "message": f"Container '{container_name}' is not currently running. Please start it first.",
            }
    except Exception as e:
        return {"status": "error", "message": f"Failed to inspect container status: {e}"}

    # Default credentials from db_info or DRIVER_CATALOG
    default_catalog = DRIVER_CATALOG.get(engine_name, DRIVER_CATALOG["postgres"])
    user = (db_info.get("user") if db_info else None) or default_catalog.get("defaultUser", "userid")
    password = (db_info.get("password") if db_info else None) or "P@55w0rd"
    database = (db_info.get("database") if db_info else None) or default_catalog.get("defaultDb", "userdata")

    cmd = []
    columns = []
    rows = []

    try:
        if engine_name in ("postgres", "pgvector", "cockroach"):
            dbname = database if database else "pgdb"
            if engine_name == "cockroach":
                cmd = [
                    container_engine, "exec", container_name,
                    "/cockroach/cockroach", "sql", "--insecure", "--database", dbname,
                    "--format", "csv", "-e", query
                ]
            else:
                # PostgreSQL psql CSV output
                cmd = [
                    container_engine, "exec", "-e", f"PGPASSWORD={password}", container_name,
                    "psql", "-U", user, "-d", dbname, "--csv", "-c", query
                ]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
            if res.returncode != 0:
                err_msg = res.stderr.strip() or res.stdout.strip() or f"Query failed with exit code {res.returncode}"
                return {"status": "error", "message": err_msg}

            out = res.stdout.strip()
            if out:
                reader = csv.reader(io.StringIO(out))
                parsed_rows = list(reader)
                if parsed_rows:
                    columns = parsed_rows[0]
                    rows = parsed_rows[1:]
            else:
                columns = ["Result"]
                rows = [["Query executed successfully (no rows returned)."]]

        elif engine_name in ("mysql", "mariadb"):
            dbname = database if database else "userdata"
            cmd = [
                container_engine, "exec", container_name,
                "mysql", "-u", user, f"-p{password}", dbname,
                "--batch", "--raw", "-e", query
            ]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
            if res.returncode != 0:
                err_msg = res.stderr.strip() or res.stdout.strip() or f"Query failed with exit code {res.returncode}"
                return {"status": "error", "message": err_msg}

            out = res.stdout.strip()
            if out:
                lines = out.split("\n")
                if lines:
                    columns = lines[0].split("\t")
                    rows = [l.split("\t") for l in lines[1:] if l.strip()]
            else:
                columns = ["Result"]
                rows = [["Query executed successfully."]]

        elif engine_name == "clickhouse":
            cmd = [
                container_engine, "exec", container_name,
                "clickhouse-client", "--query", query, "--format", "JSON"
            ]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
            if res.returncode != 0:
                # Try fallback plain format
                fallback_cmd = [
                    container_engine, "exec", container_name,
                    "clickhouse-client", "--query", query, "--format", "TabSeparatedWithNames"
                ]
                fres = subprocess.run(fallback_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
                if fres.returncode != 0:
                    return {"status": "error", "message": res.stderr.strip() or fres.stderr.strip()}
                lines = fres.stdout.strip().split("\n")
                if lines and lines[0]:
                    columns = lines[0].split("\t")
                    rows = [l.split("\t") for l in lines[1:] if l.strip()]
            else:
                try:
                    ch_data = json.loads(res.stdout)
                    meta = ch_data.get("meta", [])
                    columns = [m.get("name", f"col_{i}") for i, m in enumerate(meta)]
                    ch_rows = ch_data.get("data", [])
                    rows = [[r.get(c, "") for c in columns] for r in ch_rows]
                except Exception:
                    columns = ["Result"]
                    rows = [[res.stdout.strip()]]

        elif engine_name == "mssql":
            dbname = database if database else "mssql"
            sqlcmd_script = f"""
            if [ -f /opt/mssql-tools18/bin/sqlcmd ]; then
                /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P '{password}' -d '{dbname}' -Q "{query}" -s "," -W
            else
                /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P '{password}' -d '{dbname}' -Q "{query}" -s "," -W
            fi
            """
            cmd = [container_engine, "exec", container_name, "bash", "-c", sqlcmd_script]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
            if res.returncode != 0:
                return {"status": "error", "message": res.stderr.strip() or res.stdout.strip()}
            lines = [l.strip() for l in res.stdout.strip().split("\n") if l.strip() and not l.startswith("---")]
            if lines:
                columns = [c.strip() for c in lines[0].split(",")]
                rows = [[c.strip() for c in l.split(",")] for l in lines[1:] if not l.startswith("(")]
            else:
                columns = ["Result"]
                rows = [["Query executed successfully."]]

        elif engine_name == "redis":
            cmd = [container_engine, "exec", container_name, "redis-cli", "-a", password] + query.split()
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
            if res.returncode != 0:
                return {"status": "error", "message": res.stderr.strip() or res.stdout.strip()}
            columns = ["Response"]
            rows = [[line] for line in res.stdout.strip().split("\n") if line.strip()]

        elif engine_name == "mongodb":
            dbname = database if database else "mgdb"
            cmd = [
                container_engine, "exec", container_name,
                "mongosh", "--quiet", dbname, "--eval", query
            ]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15)
            if res.returncode != 0:
                return {"status": "error", "message": res.stderr.strip() or res.stdout.strip()}
            columns = ["Document / Output"]
            rows = [[line] for line in res.stdout.strip().split("\n") if line.strip()]

        else:
            return {"status": "error", "message": f"Query execution for '{engine_name}' is not supported yet."}

        execution_time_ms = round((time.time() - start_time) * 1000, 2)
        return {
            "status": "ok",
            "columns": columns,
            "rows": rows,
            "rowCount": len(rows),
            "executionTimeMs": execution_time_ms,
        }

    except subprocess.TimeoutExpired:
        return {"status": "error", "message": "Query timed out after 20 seconds."}
    except Exception as e:
        return {"status": "error", "message": f"Unexpected execution error: {e}"}


def get_schema_tables(engine_name, container_name, db_info=None):
    """Retrieves list of tables and schemas for the selected database."""
    if engine_name in ("postgres", "pgvector", "cockroach"):
        q = """
        SELECT table_schema, table_name, table_type
        FROM information_schema.tables
        WHERE table_schema NOT IN ('information_schema', 'pg_catalog', 'crdb_internal')
        ORDER BY table_schema, table_name;
        """
    elif engine_name in ("mysql", "mariadb"):
        q = """
        SELECT table_schema, table_name, table_type
        FROM information_schema.tables
        WHERE table_schema = DATABASE()
        ORDER BY table_name;
        """
    elif engine_name == "clickhouse":
        q = "SHOW TABLES;"
    elif engine_name == "mssql":
        q = """
        SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_TYPE = 'BASE TABLE'
        ORDER BY TABLE_SCHEMA, TABLE_NAME;
        """
    elif engine_name == "mongodb":
        q = "db.getCollectionNames()"
    elif engine_name == "redis":
        q = "KEYS *"
    else:
        return []

    res = execute_database_query(engine_name, container_name, q, db_info)
    tables = []
    if res.get("status") == "ok":
        cols = [c.lower() for c in res.get("columns", [])]
        for row in res.get("rows", []):
            if len(row) == 1:
                tables.append({"schema": "default", "name": row[0], "type": "TABLE"})
            elif len(row) >= 2:
                s_idx = cols.index("table_schema") if "table_schema" in cols else 0
                n_idx = cols.index("table_name") if "table_name" in cols else 1
                t_idx = cols.index("table_type") if "table_type" in cols else -1
                t_type = row[t_idx] if t_idx != -1 and t_idx < len(row) else "TABLE"
                tables.append({"schema": row[s_idx], "name": row[n_idx], "type": t_type})
    return tables


def get_table_structure(engine_name, container_name, schema_name, table_name, db_info=None):
    """Retrieves column definitions, data types, nullability, defaults, and primary keys."""
    if not table_name:
        return []

    schema_name = schema_name or "public"

    if engine_name in ("postgres", "pgvector", "cockroach"):
        q = f"""
        SELECT
            c.column_name,
            c.data_type,
            c.is_nullable,
            COALESCE(c.column_default, '') AS column_default,
            CASE WHEN tc.constraint_type = 'PRIMARY KEY' THEN 'YES' ELSE 'NO' END AS is_primary
        FROM information_schema.columns c
        LEFT JOIN information_schema.key_column_usage kcu
            ON c.table_schema = kcu.table_schema
            AND c.table_name = kcu.table_name
            AND c.column_name = kcu.column_name
        LEFT JOIN information_schema.table_constraints tc
            ON kcu.table_schema = tc.table_schema
            AND kcu.table_name = tc.table_name
            AND kcu.constraint_name = tc.constraint_name
            AND tc.constraint_type = 'PRIMARY KEY'
        WHERE c.table_schema = '{schema_name}' AND c.table_name = '{table_name}'
        ORDER BY c.ordinal_position;
        """
    elif engine_name in ("mysql", "mariadb"):
        q = f"""
        SELECT
            COLUMN_NAME AS column_name,
            COLUMN_TYPE AS data_type,
            IS_NULLABLE AS is_nullable,
            COALESCE(COLUMN_DEFAULT, '') AS column_default,
            CASE WHEN COLUMN_KEY = 'PRI' THEN 'YES' ELSE 'NO' END AS is_primary
        FROM information_schema.columns
        WHERE table_schema = '{schema_name}' AND table_name = '{table_name}'
        ORDER BY ordinal_position;
        """
    elif engine_name == "clickhouse":
        q = f"DESCRIBE TABLE `{table_name}`;"
    elif engine_name == "mssql":
        q = f"""
        SELECT
            c.COLUMN_NAME AS column_name,
            c.DATA_TYPE AS data_type,
            c.IS_NULLABLE AS is_nullable,
            ISNULL(c.COLUMN_DEFAULT, '') AS column_default,
            'NO' AS is_primary
        FROM INFORMATION_SCHEMA.COLUMNS c
        WHERE c.TABLE_SCHEMA = '{schema_name}' AND c.TABLE_NAME = '{table_name}'
        ORDER BY c.ORDINAL_POSITION;
        """
    elif engine_name == "redis":
        return [
            {"column_name": "Key", "data_type": "string / hash / list", "is_nullable": "NO", "column_default": "", "is_primary": "YES"}
        ]
    else:
        return []

    res = execute_database_query(engine_name, container_name, q, db_info)
    columns = []
    if res.get("status") == "ok":
        col_names = [c.lower() for c in res.get("columns", [])]
        for row in res.get("rows", []):
            def get_val(col_key, fallback_idx, default=""):
                if col_key in col_names:
                    idx = col_names.index(col_key)
                    return str(row[idx]) if idx < len(row) and row[idx] is not None else default
                return str(row[fallback_idx]) if fallback_idx < len(row) and row[fallback_idx] is not None else default

            columns.append({
                "column_name": get_val("column_name", 0),
                "data_type": get_val("data_type", 1),
                "is_nullable": get_val("is_nullable", 2),
                "column_default": get_val("column_default", 3),
                "is_primary": get_val("is_primary", 4, "NO"),
            })
    return columns


def get_table_ddl(engine_name, container_name, schema_name, table_name, db_info=None):
    """Generates or reconstructs SQL CREATE TABLE DDL and indexes."""
    if not table_name:
        return "-- No table selected"

    schema_name = schema_name or "public"

    if engine_name in ("mysql", "mariadb"):
        res = execute_database_query(engine_name, container_name, f"SHOW CREATE TABLE `{schema_name}`.`{table_name}`;", db_info)
        if res.get("status") == "ok" and res.get("rows"):
            row = res["rows"][0]
            return row[1] if len(row) > 1 else str(row[0])

    if engine_name == "clickhouse":
        res = execute_database_query(engine_name, container_name, f"SHOW CREATE TABLE `{table_name}`;", db_info)
        if res.get("status") == "ok" and res.get("rows"):
            return res["rows"][0][0]

    if engine_name in ("postgres", "pgvector", "cockroach"):
        cols = get_table_structure(engine_name, container_name, schema_name, table_name, db_info)
        if not cols:
            return f"-- Table '{schema_name}.{table_name}' not found or has no columns"

        lines = [f"-- Table DDL: {schema_name}.{table_name}", f"-- Reconstructed by SpinDB Web Studio\n"]
        lines.append(f"CREATE TABLE {schema_name}.{table_name} (")
        col_defs = []
        pk_cols = []
        for c in cols:
            cname = c["column_name"]
            ctype = c["data_type"]
            nullable = "" if c["is_nullable"] == "YES" else " NOT NULL"
            default_val = f" DEFAULT {c['column_default']}" if c.get("column_default") else ""
            col_defs.append(f"    {cname} {ctype}{default_val}{nullable}")
            if c.get("is_primary") == "YES":
                pk_cols.append(cname)

        if pk_cols:
            col_defs.append(f"    CONSTRAINT pk_{table_name} PRIMARY KEY ({', '.join(pk_cols)})")

        lines.append(",\n".join(col_defs))
        lines.append(");")

        idx_res = execute_database_query(
            engine_name, container_name,
            f"SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = '{schema_name}' AND tablename = '{table_name}';",
            db_info
        )
        if idx_res.get("status") == "ok" and idx_res.get("rows"):
            lines.append("\n-- Indexes")
            for idx_row in idx_res["rows"]:
                if len(idx_row) >= 2 and "_pkey" not in str(idx_row[0]):
                    lines.append(f"{idx_row[1]};")

        return "\n".join(lines)

    if engine_name == "mssql":
        cols = get_table_structure(engine_name, container_name, schema_name, table_name, db_info)
        lines = [f"-- Table DDL for [{schema_name}].[{table_name}]", f"CREATE TABLE [{schema_name}].[{table_name}] ("]
        col_defs = [f"    [{c['column_name']}] {c['data_type']}" for c in cols]
        lines.append(",\n".join(col_defs))
        lines.append(");")
        return "\n".join(lines)

    return f"-- Schema definition for {engine_name} table '{table_name}'\n-- Generic DDL representation not available for this engine."


def seed_mock_data(engine_name, container_name, schema_name, table_name, count=10, db_info=None):
    """Inserts realistic synthetic rows into the target table."""
    try:
        count = max(1, min(int(count), 250))
    except (ValueError, TypeError):
        count = 10

    cols = get_table_structure(engine_name, container_name, schema_name, table_name, db_info)
    if not cols:
        return {"status": "error", "message": f"Table '{table_name}' has no columns or was not found."}

    insert_cols = []
    for c in cols:
        default_str = str(c.get("column_default", "")).lower()
        if "nextval(" in default_str or "generated always" in default_str or "identity" in default_str:
            continue
        insert_cols.append(c)

    if not insert_cols:
        insert_cols = cols

    col_names = [c["column_name"] for c in insert_cols]

    first_names = ["Alex", "Jordan", "Taylor", "Morgan", "Sam", "Chris", "Pat", "Robin", "Casey", "Riley", "Jamie", "Avery", "Jesse", "Dakota", "Quinn"]
    last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson"]
    domains = ["example.com", "cloudspin.io", "techlabs.org", "enterprise.dev", "dataco.net"]
    cities = ["San Francisco", "New York", "London", "Tokyo", "Berlin", "Singapore", "Sydney", "Toronto", "Amsterdam", "Paris", "Zurich", "Dublin", "Seoul", "Austin", "Boston"]
    companies = ["Apex Innovations", "BlueWave Tech", "CloudSphere", "DataMinds", "Echo Systems", "Frontier AI", "GlobalNet", "Hyperion Corp", "InfiniSoft", "JetStream Labs"]
    statuses = ["ACTIVE", "PENDING", "COMPLETED", "VERIFIED", "IN_REVIEW"]

    rows_values = []
    for i in range(1, count + 1):
        row_vals = []
        fname = first_names[(i - 1) % len(first_names)]
        lname = last_names[(i - 1 + (i // len(first_names))) % len(last_names)]
        dom = domains[(i - 1) % len(domains)]
        full_name = f"{fname} {lname}"
        email = f"{fname.lower()}.{lname.lower()}{i}@{dom}"
        city = cities[(i - 1) % len(cities)]
        comp = companies[(i - 1) % len(companies)]
        status = statuses[(i - 1) % len(statuses)]

        for c in insert_cols:
            cname = c["column_name"].lower()
            dtype = c["data_type"].lower()

            if "email" in cname:
                row_vals.append(f"'{email}'")
            elif "name" in cname or "user" in cname or "author" in cname or "customer" in cname:
                row_vals.append(f"'{full_name}'")
            elif "city" in cname or "location" in cname:
                row_vals.append(f"'{city}'")
            elif "company" in cname or "org" in cname:
                row_vals.append(f"'{comp}'")
            elif "status" in cname or "state" in cname:
                row_vals.append(f"'{status}'")
            elif "phone" in cname:
                row_vals.append(f"'+1-555-01{i:02d}'")
            elif "uuid" in cname or "guid" in cname or dtype == "uuid":
                row_vals.append(f"'{uuid.uuid4()}'")
            elif "bool" in dtype:
                row_vals.append("TRUE" if (i % 2 == 1) else "FALSE")
            elif any(t in dtype for t in ("int", "serial", "bigint", "smallint")):
                row_vals.append(str(i * 10))
            elif any(t in dtype for t in ("numeric", "decimal", "float", "double", "real")) or any(k in cname for k in ("price", "amount", "salary", "balance")):
                row_vals.append(str(round(29.95 * i, 2)))
            elif any(t in dtype for t in ("json", "jsonb")):
                row_vals.append(f"'{{\"seed\": true, \"row\": {i}, \"status\": \"{status}\"}}'")
            elif any(t in dtype for t in ("date", "time", "timestamp")):
                row_vals.append(f"'2026-0{(i % 9) + 1}-{(i % 27) + 1:02d} 10:00:00'")
            else:
                row_vals.append(f"'{cname.title()} Record {i}'")

        rows_values.append(f"({', '.join(row_vals)})")

    schema_prefix = f"{schema_name}." if schema_name and schema_name != "default" else ""
    quoted_cols = ", ".join([f'"{c}"' if engine_name in ("postgres", "pgvector", "cockroach") else f"`{c}`" if engine_name in ("mysql", "mariadb") else c for c in col_names])
    values_str = ",\n".join(rows_values)
    insert_sql = f"INSERT INTO {schema_prefix}{table_name} ({quoted_cols}) VALUES\n{values_str};"

    res = execute_database_query(engine_name, container_name, insert_sql, db_info)
    if res.get("status") == "ok":
        return {
            "status": "ok",
            "message": f"Successfully seeded {count} mock rows into '{table_name}'.",
            "count": count
        }
    return {
        "status": "error",
        "message": f"Failed to seed mock data: {res.get('message', 'Unknown database error')}"
    }


def dump_database(engine_name, container_name, db_info=None):
    """Executes database dump utility or exports schema and data as SQL."""
    c_engine = (db_info.get("runtime") if db_info else None) or resolve_container_engine()
    user = (db_info.get("user") if db_info else None) or "userid"
    password = (db_info.get("password") if db_info else None) or "P@55w0rd"
    database = (db_info.get("database") if db_info else None) or "pgdb"

    if engine_name in ("postgres", "pgvector", "cockroach"):
        cmd = [c_engine, "exec", container_name, "pg_dump", "-U", user, "-d", database, "--clean", "--if-exists"]
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40)
            if res.returncode == 0 and res.stdout:
                return res.stdout, f"{container_name}_{database}_dump.sql"
        except Exception:
            pass

    elif engine_name in ("mysql", "mariadb"):
        cmd = [c_engine, "exec", container_name, "mysqldump", "-u", user, f"-p{password}", database]
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40)
            if res.returncode == 0 and res.stdout:
                return res.stdout, f"{container_name}_{database}_dump.sql"
        except Exception:
            pass

    tables = get_schema_tables(engine_name, container_name, db_info)
    fallback_lines = [
        f"-- SpinDB Studio Database Export",
        f"-- Container: {container_name} ({engine_name})",
        f"-- Database: {database}",
        f"-- Export Date: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}",
        "\n"
    ]
    for t in tables:
        s_name = t.get("schema", "public")
        t_name = t.get("name")
        ddl = get_table_ddl(engine_name, container_name, s_name, t_name, db_info)
        fallback_lines.append(ddl)
        fallback_lines.append("\n")

    return "\n".join(fallback_lines).encode("utf-8"), f"{container_name}_{database}_dump.sql"


def execute_multi_script(engine_name, container_name, script, db_info=None):
    """Executes a multi-statement SQL script."""
    if not script or not script.strip():
        return {"status": "error", "message": "Script is empty."}

    c_engine = (db_info.get("runtime") if db_info else None) or resolve_container_engine()
    user = (db_info.get("user") if db_info else None) or "userid"
    password = (db_info.get("password") if db_info else None) or "P@55w0rd"
    database = (db_info.get("database") if db_info else None) or "pgdb"

    start_time = time.time()
    if engine_name in ("postgres", "pgvector", "cockroach"):
        cmd = [c_engine, "exec", "-i", container_name, "psql", "-U", user, "-d", database]
    elif engine_name in ("mysql", "mariadb"):
        cmd = [c_engine, "exec", "-i", container_name, "mysql", "-u", user, f"-p{password}", database]
    elif engine_name == "clickhouse":
        cmd = [c_engine, "exec", "-i", container_name, "clickhouse-client", "--multiquery"]
    else:
        return {"status": "error", "message": f"Script execution is not supported for {engine_name}."}

    try:
        res = subprocess.run(cmd, input=script, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
        elapsed = round((time.time() - start_time) * 1000, 2)
        if res.returncode != 0:
            return {
                "status": "error",
                "message": res.stderr.strip() or res.stdout.strip() or f"Script execution failed with code {res.returncode}",
                "executionTimeMs": elapsed
            }
        return {
            "status": "ok",
            "message": "Script executed successfully.",
            "output": res.stdout.strip() or "OK",
            "executionTimeMs": elapsed
        }
    except subprocess.TimeoutExpired:
        return {"status": "error", "message": "Script execution timed out after 60 seconds."}
    except Exception as e:
        return {"status": "error", "message": f"Execution error: {e}"}


def parse_jdbc_url(url):
    """Parses host, port, database, and query parameters from a JDBC or native URL."""
    clean = (url or "").strip()
    if not clean:
        return {}

    # Strip jdbc: prefix
    if clean.startswith("jdbc:"):
        clean = clean[5:]

    # SQLServer format: sqlserver://HOST:PORT;databaseName=DB;...
    if clean.startswith("sqlserver://"):
        m = re.search(r"sqlserver://([^:;/]+)(?::(\d+))?(?:;databaseName=([^;]+))?", clean)
        if m:
            return {
                "engine": "mssql",
                "host": m.group(1),
                "port": m.group(2) or "1433",
                "database": m.group(3) or "mssql"
            }

    # Standard URL: proto://[user:pass@]host[:port]/database[?query]
    if "://" in clean:
        scheme, rest = clean.split("://", 1)
        parsed = urllib.parse.urlparse("scheme://" + rest)
        db = parsed.path.lstrip("/")
        if "?" in db:
            db = db.split("?")[0]
        return {
            "engine": scheme,
            "host": parsed.hostname or "127.0.0.1",
            "port": str(parsed.port) if parsed.port else "",
            "database": db,
            "user": parsed.username or "",
            "password": parsed.password or "",
            "query": parsed.query
        }
    return {}


def test_database_connection(container_name, engine_name, jdbc_url, user=None, password=None, db_info=None):
    """Attempts connection and runs a verification probe query, returning detailed diagnostics."""
    parsed = parse_jdbc_url(jdbc_url)

    target_host = parsed.get("host") or (db_info.get("host") if db_info else "127.0.0.1")
    target_port = parsed.get("port") or (db_info.get("port") if db_info else "")
    target_db = parsed.get("database") or (db_info.get("database") if db_info else "")
    target_user = user or parsed.get("user") or (db_info.get("user") if db_info else "userid")
    target_password = password or parsed.get("password") or (db_info.get("password") if db_info else "P@55w0rd")

    # 1. Test socket reachability if port is given and host is external
    if target_port and target_host not in ("localhost", "127.0.0.1", "0.0.0.0"):
        import socket
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(3.0)
            s.connect((target_host, int(target_port)))
            s.close()
        except Exception as sock_err:
            return {
                "status": "error",
                "message": f"Network connection to {target_host}:{target_port} failed.",
                "details": f"Socket Connection Error: {sock_err}\nCould not reach database port on host '{target_host}'. Verify the host is reachable and port {target_port} is open."
            }

    # 2. Probe database query
    custom_db_info = dict(db_info or {})
    if target_db:
        custom_db_info["database"] = target_db
    if target_user:
        custom_db_info["user"] = target_user
    if target_password:
        custom_db_info["password"] = target_password
    if target_port:
        custom_db_info["port"] = target_port
    if target_host:
        custom_db_info["host"] = target_host

    if engine_name == "redis":
        probe_query = "PING"
    elif engine_name == "mongodb":
        probe_query = "db.runCommand({ ping: 1 })"
    elif engine_name == "clickhouse":
        probe_query = "SELECT 1"
    else:
        probe_query = "SELECT 1 AS connected, current_database();" if engine_name in ("postgres", "pgvector", "cockroach") else "SELECT 1, DATABASE();"

    res = execute_database_query(engine_name, container_name, probe_query, custom_db_info)
    if res.get("status") != "ok":
        return {
            "status": "error",
            "message": f"Database handshake failed for '{target_db or 'default'}'.",
            "details": res.get("message", "Unknown query failure during connection test.")
        }

    return {
        "status": "ok",
        "message": f"Connection verified successfully to {target_host}:{target_port}/{target_db}",
        "parsed": {
            "host": target_host,
            "port": target_port,
            "database": target_db,
            "user": target_user,
            "latencyMs": res.get("executionTimeMs", 0)
        }
    }


STUDIO_HTML_FILE = SCRIPT_DIR / "static" / "studio.html"
FALLBACK_HTML_FILE = PROJECT_ROOT / "lib" / "studio.html"


def get_studio_html():
    """Loads studio HTML from static/studio.html with fallback."""
    for html_path in [STUDIO_HTML_FILE, SCRIPT_DIR / "studio.html", FALLBACK_HTML_FILE]:
        if html_path.exists():
            with open(html_path, "r", encoding="utf-8") as f:
                return f.read()
    return "<!DOCTYPE html><html><body><h3>SpinDB Web Studio HTML file not found</h3></body></html>"


class SpinDBStudioHandler(BaseHTTPRequestHandler):
    """HTTP Request Handler serving Studio Web App & REST Endpoints."""

    def log_message(self, format, *args):
        # Concise logging to stdout
        sys.stdout.write(f"[STUDIO] {self.address_string()} - {format % args}\n")

    def send_json(self, data, status_code=200):
        body = json.dumps(data).encode("utf-8")
        try:
            self.send_response(status_code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query_params = urllib.parse.parse_qs(parsed.query)

        if path in ("/", "/index.html"):
            containers = get_running_containers()
            catalog_copy = {}
            for k, v in DRIVER_CATALOG.items():
                v_copy = dict(v)
                v_copy["isDownloaded"] = check_driver_downloaded(v.get("fileName"))
                catalog_copy[k] = v_copy

            init_script = (
                f"<script>\n"
                f"  window.__INITIAL_CONTAINERS__ = {json.dumps(containers)};\n"
                f"  window.__INITIAL_DRIVERS__ = {json.dumps(catalog_copy)};\n"
                f"</script>"
            )
            raw_html = get_studio_html()
            html = raw_html.replace("<!-- INITIAL_DATA -->", init_script)
            body = html.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.end_headers()
            self.wfile.write(body)
            return

        if path == "/api/containers":
            engine = resolve_container_engine()
            containers = get_running_containers()
            self.send_json({"status": "ok", "engine": engine, "containers": containers})
            return

        if path == "/api/drivers":
            # Augment catalog with local file presence
            catalog_copy = {}
            for k, v in DRIVER_CATALOG.items():
                v_copy = dict(v)
                v_copy["isDownloaded"] = check_driver_downloaded(v.get("fileName"))
                catalog_copy[k] = v_copy
            self.send_json({"status": "ok", "drivers": catalog_copy})
            return

        if path == "/api/versions":
            engine = query_params.get("engine", ["postgres"])[0].lower()
            try:
                res = subprocess.run(
                    [str(SPINCTL_BIN), "versions", engine, "--json"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=5
                )
                if res.returncode == 0 and res.stdout.strip():
                    data = json.loads(res.stdout)
                    self.send_json(data)
                    return
                else:
                    self.send_json({"status": "error", "message": res.stderr.strip() or "Failed to query versions"}, status=500)
                    return
            except Exception as e:
                self.send_json({"status": "error", "message": str(e)}, status=500)
                return

        if path == "/api/download-jar":
            engine_key = query_params.get("engine", ["postgres"])[0].lower()
            driver = DRIVER_CATALOG.get(engine_key, DRIVER_CATALOG["postgres"])
            target_url = driver["downloadUrl"]
            file_name = driver["fileName"]

            # Redirect directly to Maven download or stream
            self.send_response(HTTPStatus.FOUND)
            self.send_header("Location", target_url)
            self.end_headers()
            return

        if path == "/api/schema":
            cname = query_params.get("container", [""])[0]
            engine = query_params.get("engine", ["postgres"])[0]
            containers = get_running_containers()
            db_info = next((c for c in containers if c["name"] == cname), None)
            tables = get_schema_tables(engine, cname, db_info)
            self.send_json({"status": "ok", "tables": tables})
            return

        if path == "/api/table-structure":
            cname = query_params.get("container", [""])[0]
            engine = query_params.get("engine", ["postgres"])[0]
            schema = query_params.get("schema", [""])[0]
            table = query_params.get("table", [""])[0]
            containers = get_running_containers()
            db_info = next((c for c in containers if c["name"] == cname), None)
            columns = get_table_structure(engine, cname, schema, table, db_info)
            self.send_json({"status": "ok", "columns": columns, "table": table, "schema": schema})
            return

        if path == "/api/table-ddl":
            cname = query_params.get("container", [""])[0]
            engine = query_params.get("engine", ["postgres"])[0]
            schema = query_params.get("schema", [""])[0]
            table = query_params.get("table", [""])[0]
            containers = get_running_containers()
            db_info = next((c for c in containers if c["name"] == cname), None)
            ddl = get_table_ddl(engine, cname, schema, table, db_info)
            self.send_json({"status": "ok", "ddl": ddl, "table": table, "schema": schema})
            return

        if path == "/api/dump":
            cname = query_params.get("container", [""])[0]
            engine = query_params.get("engine", ["postgres"])[0]
            containers = get_running_containers()
            db_info = next((c for c in containers if c["name"] == cname), None)
            dump_data, filename = dump_database(engine, cname, db_info)
            self.send_response(200)
            self.send_header("Content-Type", "application/sql")
            self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
            self.send_header("Content-Length", str(len(dump_data)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(dump_data)
            return

        if path == "/docs":
            docs_file = PROJECT_ROOT / "docs" / "DATABASE_GUIDE.md"
            if docs_file.exists():
                with open(docs_file, "r", encoding="utf-8") as f:
                    content = f.read()
                body = f"<pre style='background:#1e293b; color:#f8fafc; padding:20px; font-family:monospace;'>{content}</pre>".encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return

        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else b"{}"
        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception:
            payload = {}

        if path == "/api/query":
            cname = payload.get("container", "")
            engine = payload.get("engine", "postgres")
            query = payload.get("query", "")
            containers = get_running_containers()
            db_info = next((c for c in containers if c["name"] == cname), None)

            result = execute_database_query(engine, cname, query, db_info)
            self.send_json(result)
            return

        if path == "/api/reconnect":
            cname = payload.get("container", "")
            engine = payload.get("engine", "postgres")
            jdbc_url = payload.get("jdbcUrl", "")
            user = payload.get("user")
            password = payload.get("password")

            containers = get_running_containers()
            db_info = next((c for c in containers if c["name"] == cname), None)

            res = test_database_connection(cname, engine, jdbc_url, user, password, db_info)
            self.send_json(res)
            return

        if path == "/api/seed-mock-data":
            cname = payload.get("container", "")
            engine = payload.get("engine", "postgres")
            schema = payload.get("schema", "")
            table = payload.get("table", "")
            count = payload.get("count", 10)
            containers = get_running_containers()
            db_info = next((c for c in containers if c["name"] == cname), None)
            res = seed_mock_data(engine, cname, schema, table, count, db_info)
            self.send_json(res)
            return

        if path == "/api/execute-script":
            cname = payload.get("container", "")
            engine = payload.get("engine", "postgres")
            script = payload.get("script", "")
            containers = get_running_containers()
            db_info = next((c for c in containers if c["name"] == cname), None)
            res = execute_multi_script(engine, cname, script, db_info)
            self.send_json(res)
            return

        if path == "/api/download-driver":
            engine = payload.get("engine", "postgres").lower()
            driver = DRIVER_CATALOG.get(engine, DRIVER_CATALOG["postgres"])
            download_url = driver["downloadUrl"]
            file_name = driver["fileName"]
            dest_path = LIB_DIR / file_name

            try:
                LIB_DIR.mkdir(parents=True, exist_ok=True)
                req = urllib.request.Request(
                    download_url,
                    headers={"User-Agent": "SpinDB-Studio/1.0"}
                )
                with urllib.request.urlopen(req, timeout=30) as response, open(dest_path, "wb") as out_file:
                    shutil.copyfileobj(response, out_file)

                self.send_json({
                    "status": "ok",
                    "fileName": file_name,
                    "path": str(dest_path),
                    "size": dest_path.stat().st_size
                })
            except Exception as e:
                self.send_json({"status": "error", "message": str(e)}, status_code=500)
            return

        if path == "/api/spin":
            engine = payload.get("engine", "postgres")
            name = payload.get("name", "")
            port = payload.get("port", "")
            version = payload.get("version", "latest")

            cmd = [str(SPINCTL_BIN), "-t", engine, "-v", version]
            if name:
                cmd += ["-n", name]
            if port:
                cmd += ["-p", port]

            try:
                # Non-blocking launch in thread
                def _launch():
                    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                t = threading.Thread(target=_launch, daemon=True)
                t.start()
                self.send_json({"status": "ok", "message": f"Launching {engine} container in background."})
            except Exception as e:
                self.send_json({"status": "error", "message": str(e)}, status_code=500)
            return

        if path == "/api/container-action":
            action = payload.get("action", "")
            name = payload.get("name", "")
            containers = get_running_containers()
            db_info = next((c for c in containers if c["name"] == name), None)
            c_engine = (db_info.get("runtime") if db_info else None) or resolve_container_engine()
            if action in ("start", "stop", "restart") and name:
                try:
                    res = subprocess.run([c_engine, action, name], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
                    if res.returncode == 0:
                        self.send_json({"status": "ok"})
                    else:
                        self.send_json({"status": "error", "message": res.stderr.strip()})
                except Exception as e:
                    self.send_json({"status": "error", "message": str(e)}, status_code=500)
            else:
                self.send_json({"status": "error", "message": "Invalid container action or name."}, status_code=400)
            return

        self.send_response(404)
        self.end_headers()


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def run_studio_server(port=8080, target_container=None, auto_open=False):
    """Starts the SpinDB Web Studio HTTP server."""
    httpd = None
    target_port = port
    for p in range(port, port + 50):
        try:
            httpd = ReusableHTTPServer(("127.0.0.1", p), SpinDBStudioHandler)
            target_port = p
            break
        except OSError:
            continue

    if not httpd:
        sys.stderr.write(f"[ERROR] Could not bind SpinDB Web Studio to any port in range {port}-{port+50}\n")
        sys.exit(1)

    url = f"http://127.0.0.1:{target_port}"

    print("=" * 76)
    print("  ⚡ SpinDB Web Studio - Database & SQL Management UI")
    print("=" * 76)
    print(f"  Web Studio URL:  {url}")
    print(f"  Active Runtime:  {resolve_container_engine()}")
    print("  Features:")
    print("    * Auto-detect all running SpinDB instances")
    print("    * Interactive SQL Query Runner & Tabular Result Grid")
    print("    * Live Connection Parameters & Editable JDBC URL Bar")
    print("    * Official JDBC Driver Center & 1-Click JAR Downloader")
    print("=" * 76)
    print("  Press Ctrl+C to stop the Web Studio server.\n")

    if auto_open:
        try:
            import webbrowser
            threading.Timer(1.0, lambda: webbrowser.open(url)).start()
        except Exception:
            pass

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[INFO] Stopping SpinDB Web Studio server...")
        httpd.server_close()


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="SpinDB Web Studio - Database & SQL Client UI")
    parser.add_argument("-p", "--port", type=int, default=8080, help="Web Studio port (Default: 8080)")
    parser.add_argument("-n", "--target", type=str, default=None, help="Target container name to pre-select")
    parser.add_argument("--open", action="store_true", help="Automatically open browser")
    args = parser.parse_args()

    run_studio_server(port=args.port, target_container=args.target, auto_open=args.open)
