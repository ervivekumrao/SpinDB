#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/unit/test_port.sh - Unit Tests for Port Allocation & Dynamic Naming
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/port.sh"

test_suite_start "Port Allocation & Dynamic Naming Subsystem (lib/port.sh)"

test_normalize_engine_name() {
  assert_equals "mysql" "$(normalize_engine_name "mysql")" "mysql normalization failed"
  assert_equals "mariadb" "$(normalize_engine_name "mariadb")" "mariadb normalization failed"
  assert_equals "postgres" "$(normalize_engine_name "postgres")" "postgres normalization failed"
  assert_equals "postgres" "$(normalize_engine_name "postgresql")" "postgresql alias failed"
  assert_equals "pgvector" "$(normalize_engine_name "pgvector")" "pgvector failed"
  assert_equals "mssql" "$(normalize_engine_name "mssql")" "mssql normalization failed"
  assert_equals "mssql" "$(normalize_engine_name "sql server")" "sql server normalization failed"
  assert_equals "redis" "$(normalize_engine_name "redis")" "redis normalization failed"
  assert_equals "redis" "$(normalize_engine_name "valkey")" "valkey normalization failed"
  assert_equals "clickhouse" "$(normalize_engine_name "clickhouse")" "clickhouse normalization failed"
  assert_equals "databricks" "$(normalize_engine_name "spark-delta")" "spark-delta normalization failed"
}

test_default_engine_ports() {
  assert_equals "3306" "$(get_default_port_for_engine "mysql")" "Wrong port for mysql"
  assert_equals "3306" "$(get_default_port_for_engine "mariadb")" "Wrong port for mariadb"
  assert_equals "5432" "$(get_default_port_for_engine "postgres")" "Wrong port for postgres"
  assert_equals "5432" "$(get_default_port_for_engine "pgvector")" "Wrong port for pgvector"
  assert_equals "1433" "$(get_default_port_for_engine "mssql")" "Wrong port for mssql"
  assert_equals "1521" "$(get_default_port_for_engine "oracle")" "Wrong port for oracle"
  assert_equals "27017" "$(get_default_port_for_engine "mongodb")" "Wrong port for mongodb"
  assert_equals "6379" "$(get_default_port_for_engine "redis")" "Wrong port for redis"
  assert_equals "8123" "$(get_default_port_for_engine "clickhouse")" "Wrong port for clickhouse"
  assert_equals "26257" "$(get_default_port_for_engine "cockroach")" "Wrong port for cockroach"
  assert_equals "8080" "$(get_default_port_for_engine "snowflake")" "Wrong port for snowflake"
  assert_equals "50000" "$(get_default_port_for_engine "db2")" "Wrong port for db2"
  assert_equals "10000" "$(get_default_port_for_engine "databricks")" "Wrong port for databricks"
}

test_resolve_instance_name() {
  # Option D: Port-linked default naming
  assert_equals "mysql-3306" "$(resolve_instance_name "mysql" 3306 "")" "Default mysql name mismatch"
  assert_equals "mysql-3307" "$(resolve_instance_name "mysql" 3307 "")" "Auto-allocated mysql name mismatch"
  assert_equals "postgres-5432" "$(resolve_instance_name "postgres" 5432 "")" "Default postgres name mismatch"
  assert_equals "redis-6379" "$(resolve_instance_name "redis" 6379 "")" "Default redis name mismatch"
  assert_equals "redis-6380" "$(resolve_instance_name "redis" 6380 "")" "Auto-allocated redis name mismatch"
  
  # Custom explicit name override preserved
  assert_equals "custom-db-instance" "$(resolve_instance_name "mysql" 3306 "custom-db-instance")" "Explicit name override failed"
}

test_auto_allocate_free_port() {
  # Port 49152+ are IANA ephemeral ports, typically free
  local test_base=49152
  local free_port
  free_port="$(auto_allocate_port "${test_base}" "127.0.0.1")"
  if [[ -z "${free_port}" || "${free_port}" -lt "${test_base}" ]]; then
    echo "Failed to allocate free port above ${test_base}" >&2
    return 1
  fi
  return 0
}

run_test "Normalize engine vendor names and aliases" test_normalize_engine_name
run_test "Verify default ports for all 12 engines" test_default_engine_ports
run_test "Option D Port-linked naming resolution (engine-port)" test_resolve_instance_name
run_test "Auto-allocation of free sequential ports" test_auto_allocate_free_port

test_suite_end
