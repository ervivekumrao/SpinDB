#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# lib/lifecycle.sh - Container Lifecycle Operations (status, logs, stop, rm)
# ==============================================================================

[[ -n "${_LIB_LIFECYCLE_LOADED:-}" ]] && return 0
_LIB_LIFECYCLE_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=lib/versions.sh
source "${PROJECT_ROOT}/lib/versions.sh"

resolve_lifecycle_engine() {
  if [[ -n "${CONTAINER_ENGINE}" ]]; then
    return 0
  fi
  if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    CONTAINER_ENGINE="podman"
  elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    CONTAINER_ENGINE="docker"
  elif command -v docker >/dev/null 2>&1; then
    CONTAINER_ENGINE="docker"
  elif command -v podman >/dev/null 2>&1; then
    CONTAINER_ENGINE="podman"
  else
    log_error "Neither operational podman nor docker is available."
    exit 1
  fi
}

handle_lifecycle_command() {
  local action="$1"
  local target="$2"

  case "${action}" in
    versions|list-versions|list_versions)
      local engine="${target}"
      local filter="${3:-}"
      local refresh=false
      local offline=false
      for arg in "$@"; do
        if [[ "${arg,,}" == "--refresh" || "${arg,,}" == "--no-cache" ]]; then
          refresh=true
        elif [[ "${arg,,}" == "--offline" ]]; then
          offline=true
        fi
      done
      if [[ "${engine,,}" == "--refresh" || "${engine,,}" == "--no-cache" || "${engine,,}" == "--offline" ]]; then
        engine=""
      fi
      if [[ "${filter,,}" == "--refresh" || "${filter,,}" == "--no-cache" || "${filter,,}" == "--offline" ]]; then
        filter=""
      fi
      if [[ -z "${engine}" || "${engine}" == "all" ]]; then
        list_all_supported_engines_matrix "${refresh}" "${offline}"
      else
        list_engine_versions "${engine}" "${filter}" "${refresh}" "${offline}"
      fi
      exit 0
      ;;
  esac

  resolve_lifecycle_engine

  case "${action}" in
    status)
      if [[ -n "${target}" && "${target}" != "all" ]]; then
        log_info "Status for container '${target}' (${CONTAINER_ENGINE}):"
        "${CONTAINER_ENGINE}" ps -a --filter "name=${target}"
      else
        log_info "All SpinDB managed containers (${CONTAINER_ENGINE}):"
        local labeled_count
        labeled_count="$("${CONTAINER_ENGINE}" ps -a --filter "label=app=spindb" --format '{{.Names}}' 2>/dev/null | wc -l || echo "0")"
        if [[ "${labeled_count}" -gt 0 ]]; then
          "${CONTAINER_ENGINE}" ps -a --filter "label=app=spindb" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
        else
          # Fallback to general container list
          "${CONTAINER_ENGINE}" ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
        fi
      fi
      exit 0
      ;;

    start)
      if [[ -z "${target}" ]]; then
        log_error "Target container name required for 'start'. Usage: spinctl start <name>"
        exit 1
      fi
      log_info "Starting container '${target}'..."
      "${CONTAINER_ENGINE}" start "${target}"
      exit 0
      ;;

    restart)
      if [[ -z "${target}" ]]; then
        log_error "Target container name required for 'restart'. Usage: spinctl restart <name>"
        exit 1
      fi
      log_info "Restarting container '${target}'..."
      "${CONTAINER_ENGINE}" restart "${target}"
      exit 0
      ;;

    stop)
      if [[ "${target}" == "--all" || "${target}" == "all" ]]; then
        log_info "Stopping all SpinDB containers..."
        local ids
        ids="$("${CONTAINER_ENGINE}" ps -q --filter "label=app=spindb" 2>/dev/null || true)"
        if [[ -n "${ids}" ]]; then
          echo "${ids}" | xargs -r "${CONTAINER_ENGINE}" stop
        fi
        exit 0
      fi
      local name="${target:-${CONTAINER_DB_NAME:-localdb}}"
      log_info "Stopping container '${name}'..."
      "${CONTAINER_ENGINE}" stop "${name}"
      exit 0
      ;;

    logs)
      local name="${target:-${CONTAINER_DB_NAME:-localdb}}"
      log_info "Following logs for '${name}'..."
      "${CONTAINER_ENGINE}" logs -f "${name}"
      exit 0
      ;;

    rm|remove)
      if [[ "${target}" == "--all" || "${target}" == "all" ]]; then
        log_info "Removing all SpinDB containers..."
        local ids
        ids="$("${CONTAINER_ENGINE}" ps -a -q --filter "label=app=spindb" 2>/dev/null || true)"
        if [[ -n "${ids}" ]]; then
          echo "${ids}" | xargs -r "${CONTAINER_ENGINE}" rm -f
        fi
        exit 0
      fi
      local name="${target:-${CONTAINER_DB_NAME:-localdb}}"
      log_info "Stopping and removing container '${name}'..."
      "${CONTAINER_ENGINE}" rm -f "${name}"
      exit 0
      ;;

    connect|cli)
      if [[ -z "${target}" ]]; then
        log_error "Target container name required for 'connect'. Usage: spinctl connect <container-name>"
        exit 1
      fi
      log_info "Connecting interactive terminal to '${target}'..."
      local engine_type
      engine_type="$("${CONTAINER_ENGINE}" inspect -f '{{index .Config.Labels "spindb.engine"}}' "${target}" 2>/dev/null || echo "")"

      case "${engine_type}" in
        postgres|postgresql|pgvector)
          "${CONTAINER_ENGINE}" exec -it "${target}" sh -c 'psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"' || \
          "${CONTAINER_ENGINE}" exec -it "${target}" sh
          ;;
        mysql|mariadb)
          "${CONTAINER_ENGINE}" exec -it "${target}" sh -c 'mysql -u "${MYSQL_USER:-root}" -p"${MYSQL_PASSWORD:-${MYSQL_ROOT_PASSWORD}}" "${MYSQL_DATABASE}"' || \
          "${CONTAINER_ENGINE}" exec -it "${target}" sh
          ;;
        redis|valkey)
          "${CONTAINER_ENGINE}" exec -it "${target}" sh -c 'if [ -n "$REDIS_PASSWORD" ]; then redis-cli -a "$REDIS_PASSWORD"; else redis-cli; fi' || \
          "${CONTAINER_ENGINE}" exec -it "${target}" sh
          ;;
        mongodb)
          "${CONTAINER_ENGINE}" exec -it "${target}" mongosh || "${CONTAINER_ENGINE}" exec -it "${target}" sh
          ;;
        clickhouse)
          "${CONTAINER_ENGINE}" exec -it "${target}" clickhouse-client || "${CONTAINER_ENGINE}" exec -it "${target}" sh
          ;;
        cockroach|cockroachdb)
          "${CONTAINER_ENGINE}" exec -it "${target}" /cockroach/cockroach sql --insecure || "${CONTAINER_ENGINE}" exec -it "${target}" sh
          ;;
        mssql)
          "${CONTAINER_ENGINE}" exec -it "${target}" bash -c 'if [ -f /opt/mssql-tools18/bin/sqlcmd ]; then /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "${MSSQL_SA_PASSWORD}"; else /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "${MSSQL_SA_PASSWORD}"; fi' || \
          "${CONTAINER_ENGINE}" exec -it "${target}" bash
          ;;
        *)
          # Fallback to interactive shell
          "${CONTAINER_ENGINE}" exec -it "${target}" bash 2>/dev/null || "${CONTAINER_ENGINE}" exec -it "${target}" sh
          ;;
      esac
      exit 0
      ;;

    env)
      if [[ -z "${target}" ]]; then
        log_error "Target container name required for 'env'. Usage: spinctl env <container-name>"
        exit 1
      fi
      local engine_type ports
      engine_type="$("${CONTAINER_ENGINE}" inspect -f '{{index .Config.Labels "spindb.engine"}}' "${target}" 2>/dev/null || echo "database")"
      ports="$("${CONTAINER_ENGINE}" port "${target}" 2>/dev/null || echo "")"
      local host_port
      host_port="$(echo "${ports}" | head -n 1 | awk -F ':' '{print $NF}' || echo "")"
      
      printf "# SpinDB Connection Environment for: %s (%s)\n" "${target}" "${engine_type}"
      printf "DATABASE_HOST=127.0.0.1\n"
      printf "DATABASE_PORT=%s\n" "${host_port}"
      printf "DATABASE_NAME=%s\n" "$("${CONTAINER_ENGINE}" inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "${target}" | grep -E '^(POSTGRES_DB|MYSQL_DATABASE|MARIADB_DATABASE|CLICKHOUSE_DB|MONGO_INITDB_DATABASE)=' | head -n 1 | cut -d= -f2- || echo "localdb")"
      printf "DATABASE_USER=%s\n" "$("${CONTAINER_ENGINE}" inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "${target}" | grep -E '^(POSTGRES_USER|MYSQL_USER|MARIADB_USER|CLICKHOUSE_USER|MONGO_INITDB_ROOT_USERNAME)=' | head -n 1 | cut -d= -f2- || echo "userid")"
      exit 0
      ;;
  esac
}
