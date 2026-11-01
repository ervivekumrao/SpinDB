#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# lib/health.sh - Container Readiness Probing, OCI Health Checks & State Monitoring
# ==============================================================================

[[ -n "${_LIB_HEALTH_LOADED:-}" ]] && return 0
_LIB_HEALTH_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=lib/logger.sh
source "${PROJECT_ROOT}/lib/logger.sh"
# shellcheck source=lib/port.sh
source "${PROJECT_ROOT}/lib/port.sh"

HEALTH_ARGS=()

is_container_running() {
  local name="$1"
  local running
  running="$("${CONTAINER_ENGINE}" inspect -f '{{.State.Running}}' "${name}" 2>/dev/null || echo "false")"
  [[ "${running}" == "true" ]]
}

get_container_health_status() {
  local name="$1"
  "${CONTAINER_ENGINE}" inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${name}" 2>/dev/null || echo "unknown"
}

check_socket_connectivity() {
  local host="$1"
  local port="$2"
  timeout 1 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null
}

build_healthcheck_args() {
  local engine="$1"
  local internal_port="$2"
  local user="${3:-}"
  local pass="${4:-}"
  local dbname="${5:-}"

  local norm
  norm="$(normalize_engine_name "${engine}")"

  local cmd=""
  local interval="3s"
  local timeout="3s"
  local start_period="3s"
  local retries="5"

  case "${norm}" in
    postgres|postgresql|pgvector)
      cmd="pg_isready -p ${internal_port:-5432} -U ${user:-userid} -d ${dbname:-pgdb}"
      interval="2s"
      start_period="2s"
      ;;
    mysql)
      cmd="mysqladmin ping -h 127.0.0.1 -P ${internal_port:-3306} -u root -p\"${pass:-P@55w0rd}\" || mysqladmin ping -h 127.0.0.1 -P ${internal_port:-3306} -u ${user:-userid} -p\"${pass:-P@55w0rd}\""
      interval="3s"
      start_period="5s"
      ;;
    mariadb)
      cmd="mariadb-admin ping -h 127.0.0.1 -P ${internal_port:-3306} -u root -p\"${pass:-P@55w0rd}\" || healthcheck.sh --connect || exit 1"
      interval="3s"
      start_period="5s"
      ;;
    redis|valkey)
      if [[ -n "${pass}" && "${pass}" != "REDIS_PASSWORD_VALUE" ]]; then
        cmd="redis-cli -p ${internal_port:-6379} -a \"${pass}\" ping 2>/dev/null | grep -q PONG || redis-cli -p ${internal_port:-6379} ping 2>/dev/null | grep -q PONG || exit 1"
      else
        cmd="redis-cli -p ${internal_port:-6379} ping 2>/dev/null | grep -q PONG || exit 1"
      fi
      interval="2s"
      timeout="2s"
      start_period="1s"
      ;;
    mongodb|mongo)
      cmd="mongosh --port ${internal_port:-27017} --quiet --eval \"db.adminCommand('ping').ok\" 2>/dev/null | grep -q 1 || exit 1"
      interval="3s"
      start_period="3s"
      ;;
    clickhouse)
      cmd="wget -q --spider \"http://127.0.0.1:${internal_port:-8123}/ping\" || curl -sf \"http://127.0.0.1:${internal_port:-8123}/ping\" || exit 1"
      interval="3s"
      start_period="3s"
      ;;
    cockroach|cockroachdb)
      cmd="/cockroach/cockroach node status --insecure --port=${internal_port:-26257} || exit 1"
      interval="3s"
      start_period="4s"
      ;;
    mssql)
      cmd="if [ -f /opt/mssql-tools18/bin/sqlcmd ]; then /opt/mssql-tools18/bin/sqlcmd -S localhost,${internal_port:-1433} -U sa -P \"${pass:-P@55w0rd}\" -C -Q \"SELECT 1\"; else /opt/mssql-tools/bin/sqlcmd -S localhost,${internal_port:-1433} -U sa -P \"${pass:-P@55w0rd}\" -Q \"SELECT 1\"; fi || exit 1"
      interval="5s"
      timeout="4s"
      start_period="10s"
      ;;
    snowflake)
      cmd="wget -q --spider \"http://127.0.0.1:${internal_port:-8080}/\" || curl -sf \"http://127.0.0.1:${internal_port:-8080}/\" || exit 1"
      interval="3s"
      start_period="2s"
      ;;
    oracle)
      cmd="bash -c \"</dev/tcp/127.0.0.1/${internal_port:-1521}\" || exit 1"
      interval="5s"
      start_period="10s"
      ;;
    db2|ibmdb2)
      cmd="su - ${DB2INSTANCE:-db2inst} -c \"db2 connect to ${dbname:-ibmdb};\" || exit 1"
      interval="5s"
      timeout="4s"
      start_period="15s"
      ;;
    databricks|spark-delta|delta-lake)
      cmd="bash -c \"</dev/tcp/127.0.0.1/${internal_port:-10000}\" || exit 1"
      interval="3s"
      start_period="5s"
      ;;
    *)
      cmd="bash -c \"</dev/tcp/127.0.0.1/${internal_port}\" || exit 1"
      ;;
  esac

  HEALTH_ARGS=(
    "--health-cmd" "${cmd}"
    "--health-interval" "${interval}"
    "--health-timeout" "${timeout}"
    "--health-start-period" "${start_period}"
    "--health-retries" "${retries}"
  )
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

  log_info "Container '${name}' is up on ${host_ip}:${port}. Probing active readiness (Health: starting)..."

  while [[ ${attempt} -le ${max_attempts} ]]; do
    if ! is_container_running "${name}"; then
      log_error "Container '${name}' stopped unexpectedly during initialization."
      "${CONTAINER_ENGINE}" logs "${name}" 2>&1 | tail -n 25 >&2 || true
      return 1
    fi

    health_status="$(get_container_health_status "${name}")"

    if [[ "${health_status}" == "unhealthy" ]]; then
      log_error "Container '${name}' reported unhealthy state."
      "${CONTAINER_ENGINE}" logs "${name}" 2>&1 | tail -n 25 >&2 || true
      return 1
    fi

    # Verify both TCP connection acceptance and healthy/none status
    if check_socket_connectivity "${host_ip}" "${port}"; then
      if [[ "${health_status}" == "healthy" || "${health_status}" == "none" ]]; then
        local health_tag=""
        if [[ "${health_status}" == "healthy" ]]; then
          health_tag=" ${CLR_GREEN}(healthy)${CLR_RESET}"
        fi
        log_success "Database instance '${name}' is actively accepting connections${health_tag}!"
        printf "  * Host Endpoint: ${CLR_BOLD}%s:%s${CLR_RESET}\n" "${host_ip}" "${port}"
        printf "  * Health Status: ${CLR_BOLD}%s${CLR_RESET}\n" "${health_status}"
        printf "  * Engine:        ${CLR_BOLD}%s${CLR_RESET}\n" "${CONTAINER_ENGINE}"
        printf "  * Manage:        spinctl logs %s | spinctl stop %s\n\n" "${name}" "${name}"
        return 0
      fi
    fi

    printf "."
    sleep "${sleep_interval}"
    attempt=$((attempt + 1))
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
