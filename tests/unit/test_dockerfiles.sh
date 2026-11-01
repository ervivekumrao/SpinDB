#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/unit/test_dockerfiles.sh - Validation of Dockerfiles & Container Specs
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"

test_suite_start "Container Specifications & Dockerfile Integrity"

test_all_dockerfiles_have_from() {
  local dockerfiles
  dockerfiles="$(find "${PROJECT_ROOT}/Database" -name "Dockerfile")"
  for df in ${dockerfiles}; do
    if ! grep -q "FROM " "${df}"; then
      printf "Missing FROM instruction in %s\n" "${df}" >&2
      return 1
    fi
  done
  return 0
}

test_no_world_writable_permissions() {
  # 0777 permissions should never be used
  if grep -rn "0777" "${PROJECT_ROOT}/Database" --include="Dockerfile" >/dev/null 2>&1; then
    printf "Detected insecure COPY --chmod=0777 in Dockerfiles\n" >&2
    return 1
  fi
  return 0
}

test_exposed_ports_match_defaults() {
  # Verify standard default ports in Dockerfiles
  grep -q "EXPOSE 3306" "${PROJECT_ROOT}/Database/MYSQL/Dockerfile"
  grep -q "EXPOSE 3306" "${PROJECT_ROOT}/Database/MariaDB/Dockerfile"
  grep -q "EXPOSE 5432" "${PROJECT_ROOT}/Database/PostgreSQL/Dockerfile"
  grep -q "EXPOSE 1433" "${PROJECT_ROOT}/Database/SqlServer/Dockerfile"
  grep -q "EXPOSE 1521" "${PROJECT_ROOT}/Database/Oracle/Dockerfile"
  grep -q "EXPOSE 50000" "${PROJECT_ROOT}/Database/IBMDB2/Dockerfile"
  grep -q "EXPOSE 27017" "${PROJECT_ROOT}/Database/MongoDB/Dockerfile"
  grep -q "EXPOSE 6379" "${PROJECT_ROOT}/Database/Redis/Dockerfile"
  grep -q "EXPOSE 8123" "${PROJECT_ROOT}/Database/ClickHouse/Dockerfile"
  grep -q "EXPOSE 26257" "${PROJECT_ROOT}/Database/CockroachDB/Dockerfile"
  grep -q "EXPOSE 8080" "${PROJECT_ROOT}/Database/Snowflake/Dockerfile"
  grep -q "EXPOSE 10000" "${PROJECT_ROOT}/Database/Databricks/Dockerfile"
  return 0
}

test_all_setup_scripts_have_license() {
  local files
  files="$(find "${PROJECT_ROOT}/Database" -type f \( -name "*.sh" -o -name "*.sql" -o -name "Dockerfile" \))"
  for f in ${files}; do
    if ! grep -q "SPDX-License-Identifier" "${f}"; then
      printf "Missing SPDX license header in: %s\n" "${f}" >&2
      return 1
    fi
  done
  return 0
}

run_test "All Dockerfiles contain valid FROM base image instructions" test_all_dockerfiles_have_from
run_test "No world-writable permissions (0777) in any Dockerfile" test_no_world_writable_permissions
run_test "Exposed ports match documented defaults for all 12 engines" test_exposed_ports_match_defaults
run_test "All database files have SPDX license headers" test_all_setup_scripts_have_license

test_suite_end
