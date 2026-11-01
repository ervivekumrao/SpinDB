#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/unit/test_config.sh - Unit Tests for lib/config.sh
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/config.sh"

test_suite_start "Configuration Subsystem (lib/config.sh)"

test_read_standard_key() {
  local val
  val="$(get_property 'MYSQL_PORT')"
  assert_equals "3306" "${val}" "Failed to read standard key"
}

test_substring_collision() {
  local user_id pass
  user_id="$(get_property 'MYSQL_USER_ID')"
  pass="$(get_property 'MYSQL_USER_PASSWORD')"
  assert_equals "userid" "${user_id}" "Grep collision on MYSQL_USER_ID"
  assert_equals "P@55w0rd" "${pass}" "Grep collision on MYSQL_USER_PASSWORD"
}

test_complex_passwords_with_equals() {
  local tmp_prop
  tmp_prop="$(mktemp /tmp/test_prop.XXXXXX)"
  echo "TEST_COMPLEX_PASS=MySecret=Key==123=" > "${tmp_prop}"
  echo "TEST_SPECIAL_CHARS=P@ss/word&More#!" >> "${tmp_prop}"
  
  PROPERTIES_FILE="${tmp_prop}"
  local pass1 pass2
  pass1="$(get_property 'TEST_COMPLEX_PASS')"
  pass2="$(get_property 'TEST_SPECIAL_CHARS')"
  rm -f "${tmp_prop}"
  
  assert_equals "MySecret=Key==123=" "${pass1}" "Password with multiple '=' signs got truncated!"
  assert_equals "P@ss/word&More#!" "${pass2}" "Password with special characters corrupted!"
}

test_missing_key() {
  local val
  val="$(get_property 'NON_EXISTENT_KEY_12345')"
  assert_equals "" "${val}" "Non existent key should return empty string"
}

test_local_file_override_precedence() {
  local local_prop="${PROJECT_ROOT}/Database.properties.local"
  echo "MYSQL_PORT=3309" > "${local_prop}"
  unset PROPERTIES_FILE
  
  local val
  val="$(get_property 'MYSQL_PORT')"
  rm -f "${local_prop}"
  
  assert_equals "3309" "${val}" "Database.properties.local did not override base Database.properties"
}

run_test "Read standard property" test_read_standard_key
run_test "Verify no substring collision in key lookups" test_substring_collision
run_test "Read complex password containing '=' and symbols" test_complex_passwords_with_equals
run_test "Handle non-existent key gracefully" test_missing_key
run_test "Database.properties.local override precedence" test_local_file_override_precedence

test_suite_end
