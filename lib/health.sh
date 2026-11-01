#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# lib/health.sh - Container Readiness Probing & State Monitoring
# ==============================================================================

[[ -n "${_LIB_HEALTH_LOADED:-}" ]] && return 0
_LIB_HEALTH_LOADED=1

is_container_running() {
  local name="$1"
  local running
  running="$("${CONTAINER_ENGINE}" inspect -f '{{.State.Running}}' "${name}" 2>/dev/null || echo "false")"
  [[ "${running}" == "true" ]]
}

check_socket_connectivity() {
  local host="$1"
  local port="$2"
  timeout 1 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null
}

wait_for_container_health() {
  local name="$1"
  local port="$2"
  local host_ip="${3:-127.0.0.1}"
  local max_attempts="${4:-35}"
  local sleep_interval="${5:-1}"
  local attempt=1
  local health_status=""

  if ! is_container_running "${name}"; then
    log_error "Container '${name}' failed to start."
    "${CONTAINER_ENGINE}" logs "${name}" 2>&1 | tail -n 25 >&2 || true
    return 1
  fi

  log_info "Container '${name}' is up on ${host_ip}:${port}. Probing active readiness..."

  while [[ ${attempt} -le ${max_attempts} ]]; do
    if ! is_container_running "${name}"; then
      log_error "Container '${name}' stopped unexpectedly during initialization."
      "${CONTAINER_ENGINE}" logs "${name}" 2>&1 | tail -n 25 >&2 || true
      return 1
    fi

    health_status="$("${CONTAINER_ENGINE}" inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${name}" 2>/dev/null || echo "unknown")"

    if [[ "${health_status}" == "unhealthy" ]]; then
      log_error "Container '${name}' reported unhealthy state."
      "${CONTAINER_ENGINE}" logs "${name}" 2>&1 | tail -n 25 >&2 || true
      return 1
    fi

    # Verify both TCP connection acceptance and healthy/none status
    if check_socket_connectivity "${host_ip}" "${port}"; then
      if [[ "${health_status}" == "healthy" || "${health_status}" == "none" ]]; then
        log_success "Database instance '${name}' is actively accepting connections!"
        printf "  * Host Endpoint: ${CLR_BOLD}%s:%s${CLR_RESET}\n" "${host_ip}" "${port}"
        printf "  * Engine:        ${CLR_BOLD}%s${CLR_RESET}\n" "${CONTAINER_ENGINE}"
        printf "  * Manage:        spinctl logs %s | spinctl stop %s\n\n" "${name}" "${name}"
        return 0
      fi
    fi

    printf "."
    sleep "${sleep_interval}"
    ((attempt++))
  done

  # Final check if socket is reachable even if health probe takes longer to report
  if check_socket_connectivity "${host_ip}" "${port}"; then
    log_success "Database instance '${name}' port ${port} is reachable on host!"
    return 0
  fi

  log_warn "Readiness probe timeout reached (${max_attempts}s, status: ${health_status}). Container is still running in background."
  printf "Inspect container output: ${CLR_BOLD}%s logs %s${CLR_RESET}\n" "${CONTAINER_ENGINE}" "${name}"
  return 0
}
