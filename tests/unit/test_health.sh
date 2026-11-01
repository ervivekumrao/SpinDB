#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/unit/test_health.sh - Unit Tests for Container Healthchecks & Port-Aware Probes
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/port.sh"
source "${PROJECT_ROOT}/lib/health.sh"

test_suite_start "Container Healthchecks & Port-Aware Probes (lib/health.sh)"

test_health_args_generation_all_13_engines() {
  local engines=(
    "mysql" "mariadb" "postgres" "pgvector" "mssql" "oracle"
    "mongodb" "db2" "redis" "clickhouse" "cockroach"
    "snowflake" "databricks"
  )

  for eng in "${engines[@]}"; do
    local default_p
    default_p="$(get_default_port_for_engine "${eng}")"
    build_healthcheck_args "${eng}" "${default_p}" "testuser" "testpass" "testdb"

    if [[ ${#HEALTH_ARGS[@]} -eq 0 ]]; then
      echo "Failed to generate HEALTH_ARGS for engine: ${eng}" >&2
      return 1
    fi

    # Verify standard flags are present
    local all_args="${HEALTH_ARGS[*]}"
    assert_contains "${all_args}" "--health-cmd" "Missing --health-cmd for ${eng}"
    assert_contains "${all_args}" "--health-interval" "Missing --health-interval for ${eng}"
    assert_contains "${all_args}" "--health-timeout" "Missing --health-timeout for ${eng}"
    assert_contains "${all_args}" "--health-start-period" "Missing --health-start-period for ${eng}"
    assert_contains "${all_args}" "--health-retries" "Missing --health-retries for ${eng}"
  done
  return 0
}

test_port_parameterization_when_ports_vary() {
  # Test PostgreSQL with varied internal port 5433
  build_healthcheck_args "postgres" "5433" "myuser" "mypass" "mydb"
  local pg_cmd="${HEALTH_ARGS[1]}"
  assert_contains "${pg_cmd}" "5433" "PostgreSQL healthcheck did not reflect varied port 5433"
  assert_contains "${pg_cmd}" "pg_isready" "Missing pg_isready"

  # Test MySQL with varied internal port 3307
  build_healthcheck_args "mysql" "3307" "root" "mypass" "mydb"
  local my_cmd="${HEALTH_ARGS[1]}"
  assert_contains "${my_cmd}" "3307" "MySQL healthcheck did not reflect varied port 3307"
  assert_contains "${my_cmd}" "mysqladmin" "Missing mysqladmin"

  # Test Redis with varied internal port 6380
  build_healthcheck_args "redis" "6380" "" "mypass" ""
  local redis_cmd="${HEALTH_ARGS[1]}"
  assert_contains "${redis_cmd}" "6380" "Redis healthcheck did not reflect varied port 6380"
  assert_contains "${redis_cmd}" "redis-cli" "Missing redis-cli"

  # Test ClickHouse with varied internal port 8124
  build_healthcheck_args "clickhouse" "8124" "user" "pass" "db"
  local ch_cmd="${HEALTH_ARGS[1]}"
  assert_contains "${ch_cmd}" "8124" "ClickHouse healthcheck did not reflect varied port 8124"

  # Test CockroachDB with varied internal port 26258
  build_healthcheck_args "cockroach" "26258" "" "" ""
  local cr_cmd="${HEALTH_ARGS[1]}"
  assert_contains "${cr_cmd}" "26258" "CockroachDB healthcheck did not reflect varied port 26258"
}

test_help_advertises_no_healthcheck_flag() {
  local help_out
  help_out="$("${PROJECT_ROOT}/bin/spinctl" --help)"
  assert_contains "${help_out}" "--no-healthcheck" "Missing --no-healthcheck in help"
}

run_test "Healthcheck arguments generated for all 13 supported engines" test_health_args_generation_all_13_engines
run_test "Healthcheck commands parameterize internal ports when ports vary" test_port_parameterization_when_ports_vary
run_test "Help output advertises --no-healthcheck flag" test_help_advertises_no_healthcheck_flag

test_suite_end
