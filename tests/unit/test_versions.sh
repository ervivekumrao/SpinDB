#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/unit/test_versions.sh - Unit Tests for Version Discovery & Multi-Variant Catalog
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/config.sh"
source "${PROJECT_ROOT}/lib/port.sh"
source "${PROJECT_ROOT}/lib/versions.sh"

test_suite_start "Version Discovery & Multi-Variant Subsystem (lib/versions.sh)"

test_curated_catalogs_exist_for_all_13_engines() {
  local engines=(
    "mysql" "mariadb" "postgres" "pgvector" "mssql" "oracle"
    "mongodb" "db2" "redis" "clickhouse" "cockroach"
    "snowflake" "databricks"
  )

  for eng in "${engines[@]}"; do
    local major
    major="$(get_curated_major_versions "${eng}")"
    if [[ -z "${major}" ]]; then
      echo "Missing curated major versions for engine: ${eng}" >&2
      return 1
    fi
  done
  return 0
}

test_version_tag_normalization() {
  # pgvector: 16 -> pg16, 17 -> pg17, while preserving pg16
  assert_equals "pg16" "$(normalize_engine_version "pgvector" "16")" "pgvector 16 normalization failed"
  assert_equals "pg17" "$(normalize_engine_version "pgvector" "17")" "pgvector 17 normalization failed"
  assert_equals "pg16-v0.7.4" "$(normalize_engine_version "pgvector" "pg16-v0.7.4")" "pgvector explicit tag preserved"

  # mssql: 2022 -> 2022-latest, 2019 -> 2019-latest
  assert_equals "2022-latest" "$(normalize_engine_version "mssql" "2022")" "mssql 2022 normalization failed"
  assert_equals "2019-latest" "$(normalize_engine_version "mssql" "2019")" "mssql 2019 normalization failed"

  # cockroach: 24.1.0 -> v24.1.0
  assert_equals "v24.1.0" "$(normalize_engine_version "cockroach" "24.1.0")" "cockroach 24.1.0 normalization failed"
  assert_equals "v23.2.0" "$(normalize_engine_version "cockroach" "v23.2.0")" "cockroach explicit v preserved"

  # postgres & mysql: untouched
  assert_equals "16.1" "$(normalize_engine_version "postgres" "16.1")" "postgres 16.1 normalization failed"
  assert_equals "8.4" "$(normalize_engine_version "mysql" "8.4")" "mysql 8.4 normalization failed"
}

test_multi_variant_instance_naming() {
  # Default naming without version (backward compatibility)
  assert_equals "postgres-5432" "$(resolve_instance_name "postgres" 5432 "")" "Default postgres name mismatch"
  assert_equals "postgres-5432" "$(resolve_instance_name "postgres" 5432 "" "latest")" "postgres latest name mismatch"

  # Specific version naming: postgres 16.1 on port 5432 -> postgres-16.1-5432
  assert_equals "postgres-16.1-5432" "$(resolve_instance_name "postgres" 5432 "" "16.1")" "postgres 16.1 name mismatch"
  assert_equals "postgres-15-5433" "$(resolve_instance_name "postgres" 5433 "" "15")" "postgres 15 name mismatch"
  assert_equals "postgres-14-5434" "$(resolve_instance_name "postgres" 5434 "" "14")" "postgres 14 name mismatch"
  assert_equals "postgres-17-5435" "$(resolve_instance_name "postgres" 5435 "" "17")" "postgres 17 name mismatch"

  # Other engines with subversions
  assert_equals "mysql-8.4-3306" "$(resolve_instance_name "mysql" 3306 "" "8.4")" "mysql 8.4 name mismatch"
  assert_equals "redis-7.2-6379" "$(resolve_instance_name "redis" 6379 "" "7.2")" "redis 7.2 name mismatch"

  # Explicit override takes precedence over version
  assert_equals "custom-pg-cluster" "$(resolve_instance_name "postgres" 5432 "custom-pg-cluster" "16.1")" "Explicit override failed"
}

test_ttl_cache_parsing_and_invalidation() {
  # Default TTL: 24h = 86400s
  SPINDB_CACHE_TTL=""
  assert_equals "86400" "$(get_cache_ttl_seconds)" "Default TTL mismatch"

  # 12h TTL -> 43200s
  SPINDB_CACHE_TTL="12h"
  assert_equals "43200" "$(get_cache_ttl_seconds)" "12h TTL parse failed"

  # 24h TTL -> 86400s
  SPINDB_CACHE_TTL="24h"
  assert_equals "86400" "$(get_cache_ttl_seconds)" "24h TTL parse failed"

  # Custom numeric seconds
  SPINDB_CACHE_TTL="3600"
  assert_equals "3600" "$(get_cache_ttl_seconds)" "Numeric TTL parse failed"

  # Test cache writing and validity detection
  local test_cache="/tmp/spindb-test-cache-$$.cache"
  rm -f "${test_cache}"

  local sample_tags=("17.0" "16.1" "15.0")
  write_cache_tags "${test_cache}" "postgres" "${sample_tags[@]}"

  # Must be valid immediately with 86400s TTL
  if ! is_cache_valid "${test_cache}" 86400; then
    echo "Freshly written cache reported invalid" >&2
    rm -f "${test_cache}"
    return 1
  fi

  # Must be invalid with 0s TTL
  if is_cache_valid "${test_cache}" 0; then
    echo "Cache reported valid with 0s TTL" >&2
    rm -f "${test_cache}"
    return 1
  fi

  # Verify tags read back accurately
  local read_back
  read_back="$(read_cache_tags "${test_cache}" | tr '\n' ' ' | xargs)"
  assert_equals "17.0 16.1 15.0" "${read_back}" "Cached tags read mismatch"

  rm -f "${test_cache}"
  return 0
}

test_cli_versions_command_execution() {
  # Summary of all engines
  local summary_out
  summary_out="$("${PROJECT_ROOT}/bin/spinctl" versions)"
  assert_contains "${summary_out}" "SPINDB SUPPORTED DATABASE ENGINES" "Versions summary missing header"
  assert_contains "${summary_out}" "postgres" "Versions summary missing postgres"
  assert_contains "${summary_out}" "mysql" "Versions summary missing mysql"
  assert_contains "${summary_out}" "redis" "Versions summary missing redis"

  # Engine specific versions with offline mode
  local pg_out
  pg_out="$("${PROJECT_ROOT}/bin/spinctl" versions postgres --offline)"
  assert_contains "${pg_out}" "SPINDB DATABASE IMAGE & VARIANT CATALOG: POSTGRES" "Postgres versions missing title"
  assert_contains "${pg_out}" "PostgreSQL 16" "Postgres versions missing 16"
  assert_contains "${pg_out}" "16.1" "Postgres versions missing 16.1"

  # Filtered query for subversion 16.1
  local filter_out
  filter_out="$("${PROJECT_ROOT}/bin/spinctl" versions postgres 16.1 --offline)"
  assert_contains "${filter_out}" "16.1" "Filtered versions missing 16.1"
}

test_cli_versions_json_format() {
  local json_pg
  json_pg="$("${PROJECT_ROOT}/bin/spinctl" versions postgres --json)"
  assert_contains "${json_pg}" '"status": "success"' "Postgres JSON missing success status"
  assert_contains "${json_pg}" '"engine": "postgres"' "Postgres JSON missing engine key"
  assert_contains "${json_pg}" '"defaultMajor": "16"' "Postgres JSON missing defaultMajor 16"
  assert_contains "${json_pg}" '"majorVersions":' "Postgres JSON missing majorVersions"
  assert_contains "${json_pg}" '"subVersions":' "Postgres JSON missing subVersions"

  # Validate JSON syntax with python3
  if ! echo "${json_pg}" | python3 -m json.tool >/dev/null 2>&1; then
    echo "Postgres versions --json output is not valid JSON" >&2
    return 1
  fi

  local json_redis
  json_redis="$("${PROJECT_ROOT}/bin/spinctl" versions redis --json)"
  assert_contains "${json_redis}" '"engine": "redis"' "Redis JSON missing engine key"
  if ! echo "${json_redis}" | python3 -m json.tool >/dev/null 2>&1; then
    echo "Redis versions --json output is not valid JSON" >&2
    return 1
  fi
}

run_test "Curated catalogs exist for all 13 supported engines" test_curated_catalogs_exist_for_all_13_engines
run_test "Normalize vendor-specific engine tags (pgvector, mssql, cockroach)" test_version_tag_normalization
run_test "Multi-variant instance naming (postgres-16.1-5432) & backward compatibility" test_multi_variant_instance_naming
run_test "12h/24h TTL cache parsing, write, read & invalidation" test_ttl_cache_parsing_and_invalidation
run_test "CLI 'spinctl versions' subcommand execution & filtering" test_cli_versions_command_execution
run_test "CLI 'spinctl versions <engine> --json' machine-readable format" test_cli_versions_json_format

test_suite_end

