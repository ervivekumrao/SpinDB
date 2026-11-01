#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/unit/test_engine.sh - Unit Tests for lib/engine.sh
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/engine.sh"

test_suite_start "Container Engine & Platform Diagnostics (lib/engine.sh)"

test_os_detection() {
  detect_os
  if [[ -z "${OS_NAME}" ]]; then
    printf "OS_NAME should not be empty\n" >&2
    return 1
  fi
  if [[ -z "${OS_FAMILY}" ]]; then
    printf "OS_FAMILY should not be empty\n" >&2
    return 1
  fi
  return 0
}

test_install_command_generation() {
  # Mock OS_FAMILY to debian_like
  OS_FAMILY="debian_like"
  local cmd_podman cmd_docker cmd_curl
  cmd_podman="$(get_install_command 'podman')"
  cmd_docker="$(get_install_command 'docker')"
  cmd_curl="$(get_install_command 'curl')"
  
  assert_contains "${cmd_podman}" "apt-get install -y podman" "Debian podman install command wrong"
  assert_contains "${cmd_docker}" "apt-get install -y docker" "Debian docker install command wrong"
  assert_contains "${cmd_curl}" "apt-get install -y curl" "Debian curl install command wrong"

  # Mock OS_FAMILY to rhel_like
  cmd_podman="$(get_install_command 'podman' 'rhel_like')"
  assert_contains "${cmd_podman}" "dnf install -y podman" "RHEL podman install command wrong"

  # Mock OS_FAMILY to arch_like
  cmd_podman="$(get_install_command 'podman' 'arch_like')"
  assert_contains "${cmd_podman}" "pacman -S --noconfirm podman" "Arch podman install command wrong"

  # Mock OS_FAMILY to macos
  cmd_podman="$(get_install_command 'podman' 'macos')"
  assert_contains "${cmd_podman}" "brew install podman" "macOS podman install command wrong"
}

test_preflight_on_host() {
  PREFLIGHT_ONLY=true
  # Should run and exit 0 without error on the host
  "${PROJECT_ROOT}/bin/spinctl" --preflight >/dev/null
  return 0
}

test_docker_fallback_simulation() {
  # Simulate environment where podman is hidden
  local tmp_bin
  tmp_bin="$(mktemp -d)"
  for f in /usr/bin/*; do
    b=$(basename "$f")
    if [[ "$b" != "podman" ]]; then
      ln -s "$f" "${tmp_bin}/$b" 2>/dev/null || true
    fi
  done

  local output
  output="$(PATH="${tmp_bin}" "${PROJECT_ROOT}/bin/spinctl" --preflight 2>&1)"
  rm -rf "${tmp_bin}"

  assert_contains "${output}" "Utilizing operational Docker runtime" "Did not trigger Docker fallback"
  assert_contains "${output}" "apt-get install -y podman" "Missing install command in fallback warning"
}

run_test "Detect Host Operating System" test_os_detection
run_test "Generate accurate OS-specific package manager commands" test_install_command_generation
run_test "Run preflight check on host" test_preflight_on_host
run_test "Simulate Podman missing and Docker fallback warning" test_docker_fallback_simulation

test_suite_end
