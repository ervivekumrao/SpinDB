#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/unit/test_cli.sh - Unit Tests for CLI Routing & Argument Parsing
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"

test_suite_start "CLI Interface & Argument Routing"

test_help_flags() {
  "${PROJECT_ROOT}/bin/spinctl" --help >/dev/null
  "${PROJECT_ROOT}/bin/spinctl" -h >/dev/null
  return 0
}

test_invalid_option_fails() {
  if "${PROJECT_ROOT}/bin/spinctl" --invalid-flag-xyz >/dev/null 2>&1; then
    printf "Expected invalid option to exit with non-zero\n" >&2
    return 1
  fi
  return 0
}

test_help_lists_all_13_engines() {
  local help_out
  help_out="$("${PROJECT_ROOT}/bin/spinctl" --help)"

  local expected_engines=(
    "mysql" "mariadb" "postgres" "pgvector" "mssql" "oracle"
    "mongodb" "db2" "redis" "clickhouse" "cockroach"
    "snowflake" "databricks"
  )

  for eng in "${expected_engines[@]}"; do
    assert_contains "${help_out}" "${eng}" "Help output missing engine: ${eng}"
  done
}

test_enterprise_flags_advertised() {
  local help_out
  help_out="$("${PROJECT_ROOT}/bin/spinctl" --help)"
  assert_contains "${help_out}" "--bind" "Missing --bind"
  assert_contains "${help_out}" "--bind-all" "Missing --bind-all"
  assert_contains "${help_out}" "--memory" "Missing --memory"
  assert_contains "${help_out}" "--cpus" "Missing --cpus"
  assert_contains "${help_out}" "--force" "Missing --force"
  assert_contains "${help_out}" "--rebuild" "Missing --rebuild"
}

run_test "Help flags exit 0" test_help_flags
run_test "Invalid flags exit non-zero" test_invalid_option_fails
run_test "Help output advertises all supported engines including pgvector" test_help_lists_all_13_engines
run_test "Help output advertises enterprise security & resource flags" test_enterprise_flags_advertised

test_suite_end
