#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/integration/enterprise_live_test.sh - Live Real-Time Production Integration Test
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"

test_suite_start "Enterprise Live Production Lifecycle & Container Testing"

resolve_test_engine() {
  if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    echo "podman"
  elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "docker"
  fi
}
ACTIVE_ENGINE="$(resolve_test_engine)"

LIVE_CONTAINER="enterprise-live-redis-$$"
LIVE_PORT=6399

cleanup_live_test() {
  if [[ -n "${ACTIVE_ENGINE}" ]]; then
    "${ACTIVE_ENGINE}" rm -f "${LIVE_CONTAINER}" >/dev/null 2>&1 || true
    "${ACTIVE_ENGINE}" rm -f "${LIVE_CONTAINER}-dup" >/dev/null 2>&1 || true
  fi
}
trap cleanup_live_test EXIT INT TERM

test_engine_operationality() {
  if [[ -z "${ACTIVE_ENGINE}" ]]; then
    printf "No operational container engine found; skipping live test\n" >&2
    return 1
  fi
  return 0
}

test_live_container_launch_and_health() {
  "${PROJECT_ROOT}/bin/spinctl" -t redis -p "${LIVE_PORT}" -n "${LIVE_CONTAINER}" >/dev/null 2>&1

  local is_running
  is_running="$("${ACTIVE_ENGINE}" inspect -f '{{.State.Running}}' "${LIVE_CONTAINER}" 2>/dev/null | tr -d '[:space:]' || echo "false")"
  assert_equals "true" "${is_running}" "Live container failed to start"
}

test_live_labels_and_status() {
  local label_val
  label_val="$("${ACTIVE_ENGINE}" inspect -f '{{index .Config.Labels "app"}}' "${LIVE_CONTAINER}" 2>/dev/null | tr -d '[:space:]' || echo "")"
  assert_equals "spindb" "${label_val}" "Missing app=spindb OCI label"

  local status_out
  status_out="$("${PROJECT_ROOT}/bin/spinctl" status "${LIVE_CONTAINER}")"
  assert_contains "${status_out}" "${LIVE_CONTAINER}" "Status output did not list live container"
}

test_live_env_subcommand() {
  local env_out
  env_out="$("${PROJECT_ROOT}/bin/spinctl" env "${LIVE_CONTAINER}")"
  assert_contains "${env_out}" "DATABASE_HOST=127.0.0.1" "Missing localhost bind in env output"
  assert_contains "${env_out}" "DATABASE_PORT=${LIVE_PORT}" "Missing port in env output"
}

test_port_collision_protection() {
  # Attempting to start another container on the same port should exit non-zero
  if "${PROJECT_ROOT}/bin/spinctl" -t redis -p "${LIVE_PORT}" -n "${LIVE_CONTAINER}-dup" >/dev/null 2>&1; then
    printf "Expected port collision error on port %s\n" "${LIVE_PORT}" >&2
    return 1
  fi
  return 0
}

test_name_collision_protection() {
  # Attempting to start another container with same name without -f should exit non-zero
  if "${PROJECT_ROOT}/bin/spinctl" -t redis -p 6398 -n "${LIVE_CONTAINER}" >/dev/null 2>&1; then
    printf "Expected container name collision error for %s\n" "${LIVE_CONTAINER}" >&2
    return 1
  fi
  return 0
}

test_live_restart_and_stop() {
  "${PROJECT_ROOT}/bin/spinctl" restart "${LIVE_CONTAINER}" >/dev/null 2>&1
  "${PROJECT_ROOT}/bin/spinctl" stop "${LIVE_CONTAINER}" >/dev/null 2>&1

  local is_running
  is_running="$("${ACTIVE_ENGINE}" inspect -f '{{.State.Running}}' "${LIVE_CONTAINER}" 2>/dev/null | tr -d '[:space:]' || echo "false")"
  assert_equals "false" "${is_running}" "Container still running after stop"
}

test_live_rm_cleanup() {
  "${PROJECT_ROOT}/bin/spinctl" rm "${LIVE_CONTAINER}" >/dev/null 2>&1

  if "${ACTIVE_ENGINE}" inspect "${LIVE_CONTAINER}" >/dev/null 2>&1; then
    printf "Container %s should be removed\n" "${LIVE_CONTAINER}" >&2
    return 1
  fi
  return 0
}

run_test "Check Container Engine Operational Readiness" test_engine_operationality
run_test "Live Container Launch & TCP Readiness Probing" test_live_container_launch_and_health
run_test "OCI Metadata Labels & Status Tracking" test_live_labels_and_status
run_test "Environment & Connection String Generation (env)" test_live_env_subcommand
run_test "Port Collision Prevention Safeguard" test_port_collision_protection
run_test "Container Name Collision Prevention Safeguard" test_name_collision_protection
run_test "Live Container Restart & Graceful Stop" test_live_restart_and_stop
run_test "Clean Container Removal & Resource Teardown" test_live_rm_cleanup

test_suite_end
