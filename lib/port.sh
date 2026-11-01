#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# lib/port.sh - Port Discovery, Conflict Detection & Dynamic Naming Subsystem
# ==============================================================================

[[ -n "${_LIB_PORT_LOADED:-}" ]] && return 0
_LIB_PORT_LOADED=1

normalize_engine_name() {
  local engine="${1,,}"
  case "${engine}" in
    mysql) echo "mysql" ;;
    mariadb) echo "mariadb" ;;
    postgres|postgresql) echo "postgres" ;;
    pgvector) echo "pgvector" ;;
    mssql|"sql server"|sqlserver) echo "mssql" ;;
    oracle) echo "oracle" ;;
    mongodb|mongo) echo "mongodb" ;;
    db2|ibmdb2) echo "db2" ;;
    redis|valkey) echo "redis" ;;
    clickhouse) echo "clickhouse" ;;
    cockroach|cockroachdb) echo "cockroach" ;;
    snowflake) echo "snowflake" ;;
    databricks|spark-delta|delta-lake) echo "databricks" ;;
    *) echo "${engine// /-}" ;;
  esac
}

get_default_port_for_engine() {
  local engine="${1,,}"
  case "${engine}" in
    mysql|mariadb) echo 3306 ;;
    postgres|postgresql|pgvector) echo 5432 ;;
    mssql|"sql server"|sqlserver) echo 1433 ;;
    oracle) echo 1521 ;;
    mongodb|mongo) echo 27017 ;;
    redis|valkey) echo 6379 ;;
    clickhouse) echo 8123 ;;
    cockroach|cockroachdb) echo 26257 ;;
    snowflake) echo 8080 ;;
    db2|ibmdb2) echo 50000 ;;
    databricks|spark-delta|delta-lake) echo 10000 ;;
    *) echo 3306 ;;
  esac
}

find_container_by_port() {
  local target_port="$1"
  if [[ -z "${CONTAINER_ENGINE}" ]]; then
    return 1
  fi

  local all_cids
  all_cids="$("${CONTAINER_ENGINE}" ps -a -q 2>/dev/null || true)"
  if [[ -z "${all_cids}" ]]; then
    return 1
  fi

  while IFS='|' read -r cname cstatus cports; do
    cname="${cname#/}"
    for p in ${cports}; do
      if [[ "${p}" == "${target_port}" ]]; then
        echo "${cname}|${cstatus}"
        return 0
      fi
    done
  done < <("${CONTAINER_ENGINE}" inspect --format '{{.Name}}|{{.State.Status}}|{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{.HostPort}} {{end}}{{end}}' ${all_cids} 2>/dev/null || true)

  return 1
}

is_port_in_use() {
  local port="$1"
  local host_ip="${2:-127.0.0.1}"

  # 1. Check if mapped to any container (running or stopped)
  if find_container_by_port "${port}" >/dev/null 2>&1; then
    return 0
  fi

  # 2. Check if listening on host TCP socket
  if timeout 1 bash -c "</dev/tcp/${host_ip}/${port}" 2>/dev/null; then
    return 0
  fi

  return 1
}

auto_allocate_port() {
  local base_port="$1"
  local host_ip="${2:-127.0.0.1}"
  local candidate="${base_port}"
  local max_probe=$((base_port + 200))

  while [[ "${candidate}" -le "${max_probe}" ]]; do
    if ! is_port_in_use "${candidate}" "${host_ip}"; then
      echo "${candidate}"
      return 0
    fi
    ((candidate++))
  done

  log_error "Could not find an unoccupied port between ${base_port} and ${max_probe} on ${host_ip}."
  return 1
}

show_port_conflict_error() {
  local port="$1"
  local engine="$2"
  local host_ip="${3:-127.0.0.1}"
  local container_info
  container_info="$(find_container_by_port "${port}" 2>/dev/null || true)"

  printf "\n" >&2
  if [[ -n "${container_info}" ]]; then
    local cname="${container_info%%|*}"
    local cstatus="${container_info##*|}"
    log_error "Port ${port} is already assigned to container '${cname}' (Status: ${cstatus})!"
    printf "\n${CLR_BOLD}Available Options & Next Steps:${CLR_RESET}\n" >&2
    printf "  1. ${CLR_GREEN}Automatic Allocation:${CLR_RESET} Omit '-p' to let SpinDB automatically assign the next available port:\n" >&2
    printf "       ./bin/spinctl -t %s\n" "${engine}" >&2
    printf "  2. ${CLR_GREEN}Use a Different Port:${CLR_RESET} Specify an unoccupied port:\n" >&2
    printf "       ./bin/spinctl -t %s -p <port>\n" "${engine}" >&2
    if [[ "${cstatus}" == "running" ]]; then
      printf "  3. ${CLR_GREEN}Stop Conflicting Container:${CLR_RESET} If '%s' is no longer needed:\n" "${cname}" >&2
      printf "       ./bin/spinctl stop %s\n" "${cname}" >&2
      printf "  4. ${CLR_GREEN}View Existing Container Status / Logs:${CLR_RESET}\n" >&2
      printf "       ./bin/spinctl status %s\n" "${cname}" >&2
      printf "       ./bin/spinctl logs %s\n" "${cname}" >&2
    else
      printf "  3. ${CLR_GREEN}Remove Stopped Container:${CLR_RESET} Free port %s by removing the existing container:\n" "${port}" >&2
      printf "       ./bin/spinctl rm %s\n" "${cname}" >&2
      printf "  4. ${CLR_GREEN}Restart Existing Container:${CLR_RESET} Reuse the existing instance:\n" >&2
      printf "       ./bin/spinctl start %s\n" "${cname}" >&2
    fi
  else
    log_error "Host port ${port} on ${host_ip} is already occupied by an active host service!"
    printf "\n${CLR_BOLD}Available Options & Next Steps:${CLR_RESET}\n" >&2
    printf "  1. ${CLR_GREEN}Automatic Allocation:${CLR_RESET} Omit '-p' to let SpinDB automatically assign the next available port:\n" >&2
    printf "       ./bin/spinctl -t %s\n" "${engine}" >&2
    printf "  2. ${CLR_GREEN}Use a Different Port:${CLR_RESET} Specify an unoccupied port:\n" >&2
    printf "       ./bin/spinctl -t %s -p <port>\n" "${engine}" >&2
    printf "  3. ${CLR_GREEN}Identify Host Process:${CLR_RESET} Find and manage the service bound to port %s:\n" "${port}" >&2
    printf "       lsof -i :%s  or  ss -tulpn | grep :%s\n" "${port}" "${port}" >&2
  fi
  printf "\n" >&2
}

resolve_instance_name() {
  local engine="$1"
  local port="$2"
  local explicit_name="$3"

  if [[ -n "${explicit_name}" ]]; then
    echo "${explicit_name}"
  else
    echo "$(normalize_engine_name "${engine}")-${port}"
  fi
}
