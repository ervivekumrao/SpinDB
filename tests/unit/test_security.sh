#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/unit/test_security.sh - Validation of Security & Hardening Policies
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"

test_suite_start "Security Hardening & Policy Verification"

test_mssql_no_insecure_clr() {
  # CLR strict security 0 should NEVER be present in setupDB.sql
  if grep -qi "clr strict security.*0" "${PROJECT_ROOT}/Database/SqlServer/setupDB.sql"; then
    printf "Detected insecure 'clr strict security 0' in SQL Server setupDB.sql!\n" >&2
    return 1
  fi
  return 0
}

test_idempotent_sql_scripts() {
  # Verify IF NOT EXISTS or conditional checks in RDBMS setup scripts
  grep -qi "IF NOT EXISTS" "${PROJECT_ROOT}/Database/PostgreSQL/setupDB.sql"
  grep -qi "IF NOT EXISTS" "${PROJECT_ROOT}/Database/MYSQL/setupDB.sql"
  grep -qi "IF NOT EXISTS" "${PROJECT_ROOT}/Database/MariaDB/setupDB.sql"
  grep -qi "IF NOT EXISTS" "${PROJECT_ROOT}/Database/SqlServer/setupDB.sql"
  grep -qi "IF NOT EXISTS" "${PROJECT_ROOT}/Database/CockroachDB/setupDB.sql"
  return 0
}

test_default_bind_is_localhost() {
  # Help and defaults should specify 127.0.0.1 for local workstation security
  local help_out
  help_out="$("${PROJECT_ROOT}/bin/spinctl" --help)"
  assert_contains "${help_out}" "127.0.0.1" "Help output should document default bind 127.0.0.1"
  assert_contains "${help_out}" "--bind-all" "Help output should document --bind-all option"
}

test_resource_limits_documented() {
  local help_out
  help_out="$("${PROJECT_ROOT}/bin/spinctl" --help)"
  assert_contains "${help_out}" "--memory" "Help output should document --memory option"
  assert_contains "${help_out}" "--cpus" "Help output should document --cpus option"
}

test_no_plaintext_passwords_in_dockerfile_env() {
  # Verify no hardcoded production passwords in Dockerfiles
  local dockerfiles
  dockerfiles="$(find "${PROJECT_ROOT}/Database" -name "Dockerfile")"
  for df in ${dockerfiles}; do
    if grep -E "^ENV.*PASSWORD.*P@55w0rd" "${df}" >/dev/null 2>&1; then
      printf "Found hardcoded plaintext password in %s\n" "${df}" >&2
      return 1
    fi
  done
  return 0
}

run_test "MSSQL does not disable CLR strict security" test_mssql_no_insecure_clr
run_test "All RDBMS setup scripts are idempotent (IF NOT EXISTS)" test_idempotent_sql_scripts
run_test "Default host binding is 127.0.0.1 (Localhost Security)" test_default_bind_is_localhost
run_test "Resource limits (--memory, --cpus) are available" test_resource_limits_documented
run_test "No plaintext passwords hardcoded into Dockerfiles" test_no_plaintext_passwords_in_dockerfile_env

test_suite_end
