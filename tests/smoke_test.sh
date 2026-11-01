#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/smoke_test.sh - Automated CLI Integration & Regression Test Suite
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Test 1: CLI Help output"
"${PROJECT_ROOT}/bin/spinctl" --help >/dev/null
echo "[PASS] Test 1 passed."

echo "==> Test 2: Preflight checkup"
"${PROJECT_ROOT}/bin/spinctl" --preflight >/dev/null
echo "[PASS] Test 2 passed."

echo "==> Test 3: Safe Property Extraction"
source "${PROJECT_ROOT}/lib/config.sh"
PROPERTIES_FILE="${PROJECT_ROOT}/Database.properties"
mysql_user="$(get_property 'MYSQL_USER_ID')"
if [[ "${mysql_user}" != "userid" ]]; then
  echo "[FAIL] Expected 'userid', got '${mysql_user}'"
  exit 1
fi
echo "[PASS] Test 3 passed (extracted key successfully)."

echo "==> Test 4: Verify all 12 database directories exist"
required_dbs=(
  "MYSQL" "MariaDB" "PostgreSQL" "SqlServer" "Oracle"
  "IBMDB2" "MongoDB" "Redis" "ClickHouse" "CockroachDB"
  "Snowflake" "Databricks"
)

for db in "${required_dbs[@]}"; do
  if [[ ! -d "${PROJECT_ROOT}/Database/${db}" ]]; then
    echo "[FAIL] Missing directory Database/${db}"
    exit 1
  fi
  if [[ ! -f "${PROJECT_ROOT}/Database/${db}/Dockerfile" ]]; then
    echo "[FAIL] Missing Dockerfile in Database/${db}"
    exit 1
  fi
done
echo "[PASS] Test 4 passed (all 12 database directories verified)."

echo "==> [SUCCESS] All smoke tests passed successfully!"
