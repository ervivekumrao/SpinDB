#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/unit/test_lifecycle.sh - Unit Tests for Container Lifecycle Subcommands
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/lifecycle.sh"

test_suite_start "Container Lifecycle Subcommands (lib/lifecycle.sh)"

test_help_advertises_all_lifecycle_subcommands() {
  local help_out
  help_out="$("${PROJECT_ROOT}/bin/spinctl" --help)"
  assert_contains "${help_out}" "status" "Help missing 'status'"
  assert_contains "${help_out}" "start" "Help missing 'start'"
  assert_contains "${help_out}" "restart" "Help missing 'restart'"
  assert_contains "${help_out}" "stop" "Help missing 'stop'"
  assert_contains "${help_out}" "logs" "Help missing 'logs'"
  assert_contains "${help_out}" "rm" "Help missing 'rm'"
  assert_contains "${help_out}" "connect" "Help missing 'connect'"
  assert_contains "${help_out}" "env" "Help missing 'env'"
  assert_contains "${help_out}" "versions" "Help missing 'versions'"
}

test_status_execution() {
  # Should run and exit 0 without error
  "${PROJECT_ROOT}/bin/spinctl" status >/dev/null
  return 0
}

test_missing_target_for_start() {
  # Calling start without a name should exit non-zero
  if "${PROJECT_ROOT}/bin/spinctl" start >/dev/null 2>&1; then
    printf "Expected 'spinctl start' with no argument to fail\n" >&2
    return 1
  fi
  return 0
}

test_missing_target_for_restart() {
  # Calling restart without a name should exit non-zero
  if "${PROJECT_ROOT}/bin/spinctl" restart >/dev/null 2>&1; then
    printf "Expected 'spinctl restart' with no argument to fail\n" >&2
    return 1
  fi
  return 0
}

test_missing_target_for_connect() {
  # Calling connect without a name should exit non-zero
  if "${PROJECT_ROOT}/bin/spinctl" connect >/dev/null 2>&1; then
    printf "Expected 'spinctl connect' with no argument to fail\n" >&2
    return 1
  fi
  return 0
}

test_missing_target_for_env() {
  # Calling env without a name should exit non-zero
  if "${PROJECT_ROOT}/bin/spinctl" env >/dev/null 2>&1; then
    printf "Expected 'spinctl env' with no argument to fail\n" >&2
    return 1
  fi
  return 0
}

run_test "Help advertises all lifecycle subcommands (status, start, restart, stop, logs, rm, connect, env)" test_help_advertises_all_lifecycle_subcommands
run_test "Status subcommand executes cleanly" test_status_execution
run_test "Start without target name exits non-zero" test_missing_target_for_start
run_test "Restart without target name exits non-zero" test_missing_target_for_restart
run_test "Connect without target name exits non-zero" test_missing_target_for_connect
run_test "Env without target name exits non-zero" test_missing_target_for_env

test_suite_end
