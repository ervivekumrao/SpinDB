# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

.PHONY: help preflight check lint test test-unit test-smoke status clean stop

help:
	@echo "SpinDB (spinctl) - Automation & Orchestration Tasks"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Quality & Testing Targets:"
	@echo "  preflight    Run host environment and library pre-flight checkup"
	@echo "  lint         Run bash syntax & license header validation"
	@echo "  test         Run comprehensive test suite (lint + unit + smoke + live)"
	@echo "  test-unit    Run modular unit tests only"
	@echo "  test-smoke   Run regression smoke tests only"
	@echo "  status       Show running database containers"
	@echo "  stop         Stop all running database containers"
	@echo "  clean        Safely prune dangling build cache"
	@echo ""
	@echo "Quick Engine Launchers:"
	@echo "  mysql        Launch MySQL container"
	@echo "  mariadb      Launch MariaDB container"
	@echo "  postgres     Launch PostgreSQL container"
	@echo "  pgvector     Launch PostgreSQL with pgvector AI container"
	@echo "  mssql        Launch SQL Server container"
	@echo "  oracle       Launch Oracle Free container"
	@echo "  mongodb      Launch MongoDB container"
	@echo "  redis        Launch Redis cache container"
	@echo "  clickhouse   Launch ClickHouse analytics container"
	@echo "  cockroach    Launch CockroachDB container"
	@echo "  snowflake    Launch Snowflake local emulator container"
	@echo "  databricks   Launch Databricks Spark+Delta container"

preflight check:
	@./bin/spinctl --preflight

lint:
	@chmod +x tests/lint.sh && ./tests/lint.sh

test:
	@chmod +x tests/run_all_tests.sh && ./tests/run_all_tests.sh

test-unit:
	@for t in tests/unit/test_*.sh; do chmod +x $$t && ./$$t; done

test-smoke:
	@chmod +x tests/smoke_test.sh && ./tests/smoke_test.sh

status:
	@./bin/spinctl status

mysql:
	@./bin/spinctl -t mysql -p 3306 -n local-mysql

mariadb:
	@./bin/spinctl -t mariadb -p 3306 -n local-mariadb

postgres:
	@./bin/spinctl -t postgres -p 5432 -n local-postgres

pgvector:
	@./bin/spinctl -t pgvector -p 5432 -n local-pgvector

mssql:
	@./bin/spinctl -t mssql -p 1433 -n local-mssql

oracle:
	@./bin/spinctl -t oracle -p 1521 -n local-oracle

mongodb:
	@./bin/spinctl -t mongodb -p 27017 -n local-mongodb

redis:
	@./bin/spinctl -t redis -p 6379 -n local-redis

clickhouse:
	@./bin/spinctl -t clickhouse -p 8123 -n local-clickhouse

cockroach:
	@./bin/spinctl -t cockroach -p 26257 -n local-cockroach

snowflake:
	@./bin/spinctl -t snowflake -p 8080 -n local-snowflake

databricks:
	@./bin/spinctl -t databricks -p 10000 -n local-databricks

stop:
	@./bin/spinctl stop --all

clean:
	@rm -rf build.* tmp/
	@echo "Cleaned build artifacts."
