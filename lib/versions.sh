#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# lib/versions.sh - Multi-Variant Database Version Discovery & TTL Cache Engine
# ==============================================================================

[[ -n "${_LIB_VERSIONS_LOADED:-}" ]] && return 0
_LIB_VERSIONS_LOADED=1

# Source logger, engine, config, and port if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/logger.sh
source "${PROJECT_ROOT}/lib/logger.sh"
# shellcheck source=lib/config.sh
source "${PROJECT_ROOT}/lib/config.sh"
# shellcheck source=lib/port.sh
source "${PROJECT_ROOT}/lib/port.sh"

# Default Cache TTL: 24 Hours (86,400 seconds)
DEFAULT_CACHE_TTL_SECONDS=$((24 * 3600))

# ------------------------------------------------------------------------------
# TTL & Cache Resolution
# ------------------------------------------------------------------------------

get_cache_ttl_seconds() {
  if [[ -n "${SPINDB_CACHE_TTL:-}" ]]; then
    local raw="${SPINDB_CACHE_TTL,,}"
    if [[ "${raw}" =~ ^([0-9]+)h$ ]]; then
      echo "$((${BASH_REMATCH[1]} * 3600))"
      return 0
    elif [[ "${raw}" =~ ^([0-9]+)d$ ]]; then
      echo "$((${BASH_REMATCH[1]} * 86400))"
      return 0
    elif [[ "${raw}" =~ ^([0-9]+)m$ ]]; then
      echo "$((${BASH_REMATCH[1]} * 60))"
      return 0
    elif [[ "${raw}" =~ ^[0-9]+$ ]]; then
      echo "${raw}"
      return 0
    fi
  fi

  local prop_ttl
  prop_ttl="$(get_property 'VERSION_CACHE_TTL_HOURS' 2>/dev/null || echo '')"
  if [[ -n "${prop_ttl}" && "${prop_ttl}" =~ ^[0-9]+$ ]]; then
    echo "$((prop_ttl * 3600))"
    return 0
  fi

  echo "${DEFAULT_CACHE_TTL_SECONDS}"
}

get_cache_dir() {
  local cache_dir
  if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
    cache_dir="${XDG_CACHE_HOME}/spindb/versions"
  elif [[ -n "${HOME:-}" ]]; then
    cache_dir="${HOME}/.cache/spindb/versions"
  else
    cache_dir="/tmp/spindb-cache-${UID:-1000}/versions"
  fi
  mkdir -p "${cache_dir}" 2>/dev/null || true
  echo "${cache_dir}"
}

get_cache_file_for_engine() {
  local engine="$1"
  local norm
  norm="$(normalize_engine_name "${engine}")"
  local cdir
  cdir="$(get_cache_dir)"
  echo "${cdir}/${norm}.cache"
}

is_cache_valid() {
  local cache_file="$1"
  local ttl_sec="$2"

  if [[ ! -f "${cache_file}" ]]; then
    return 1
  fi

  local current_time
  current_time="$(date +%s)"
  local cache_timestamp
  cache_timestamp="$(grep -m 1 -E '^# SPINDB_CACHE_TIMESTAMP=' "${cache_file}" 2>/dev/null | cut -d= -f2 || echo 0)"

  if [[ -z "${cache_timestamp}" || ! "${cache_timestamp}" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  local age=$((current_time - cache_timestamp))
  if [[ ${age} -ge 0 && ${age} -lt ${ttl_sec} ]]; then
    return 0
  fi

  return 1
}

get_cache_age_human() {
  local cache_file="$1"
  if [[ ! -f "${cache_file}" ]]; then
    echo "none"
    return 0
  fi

  local current_time
  current_time="$(date +%s)"
  local cache_timestamp
  cache_timestamp="$(grep -m 1 -E '^# SPINDB_CACHE_TIMESTAMP=' "${cache_file}" 2>/dev/null | cut -d= -f2 || echo 0)"

  if [[ -z "${cache_timestamp}" || ! "${cache_timestamp}" =~ ^[0-9]+$ ]]; then
    echo "unknown"
    return 0
  fi

  local diff=$((current_time - cache_timestamp))
  if [[ ${diff} -lt 60 ]]; then
    echo "${diff}s ago"
  elif [[ ${diff} -lt 3600 ]]; then
    echo "$((diff / 60))m ago"
  elif [[ ${diff} -lt 86400 ]]; then
    echo "$((diff / 3600))h ago"
  else
    echo "$((diff / 86400))d ago"
  fi
}

write_cache_tags() {
  local cache_file="$1"
  local engine="$2"
  shift 2
  local tags=("$@")

  local tmp_file="${cache_file}.tmp.$$"
  {
    echo "# SPINDB_CACHE_TIMESTAMP=$(date +%s)"
    echo "# SPINDB_CACHE_ENGINE=${engine}"
    for tag in "${tags[@]}"; do
      [[ -n "${tag}" ]] && echo "${tag}"
    done
  } > "${tmp_file}" 2>/dev/null && mv -f "${tmp_file}" "${cache_file}" 2>/dev/null || rm -f "${tmp_file}" 2>/dev/null
}

read_cache_tags() {
  local cache_file="$1"
  if [[ -f "${cache_file}" ]]; then
    grep -v -E '^#' "${cache_file}" | grep -v '^[[:space:]]*$' || true
  fi
}

# ------------------------------------------------------------------------------
# Image Tag Normalization
# ------------------------------------------------------------------------------

normalize_engine_version() {
  local engine
  engine="$(normalize_engine_name "$1")"
  local raw_version="${2:-latest}"

  case "${engine}" in
    pgvector)
      # Normalize e.g. 16 -> pg16, 17 -> pg17, while preserving pg16, pg16-v0.8.0
      if [[ "${raw_version}" =~ ^[0-9]+$ ]]; then
        echo "pg${raw_version}"
      else
        echo "${raw_version}"
      fi
      ;;
    mssql)
      # Normalize 2022 -> 2022-latest, 2019 -> 2019-latest
      if [[ "${raw_version}" =~ ^(2017|2019|2022)$ ]]; then
        echo "${raw_version}-latest"
      else
        echo "${raw_version}"
      fi
      ;;
    cockroach)
      # Normalize e.g. 24.1.0 -> v24.1.0
      if [[ "${raw_version}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)? ]]; then
        echo "v${raw_version}"
      else
        echo "${raw_version}"
      fi
      ;;
    *)
      echo "${raw_version}"
      ;;
  esac
}

clean_version_for_container_name() {
  local ver="$1"
  # Replace characters forbidden in container names (/ : @ whitespace) with -
  ver="${ver//[\/:@ ]/-}"
  # Strip leading or trailing hyphens and dots
  ver="${ver##[-.]}"
  ver="${ver%%[-.]}"
  echo "${ver}"
}

# ------------------------------------------------------------------------------
# Base Image Repositories for All 13 Engines
# ------------------------------------------------------------------------------

get_base_image_repo_for_engine() {
  local engine
  engine="$(normalize_engine_name "$1")"
  case "${engine}" in
    mysql)       echo "docker.io/library/mysql" ;;
    mariadb)     echo "docker.io/library/mariadb" ;;
    postgres)    echo "docker.io/library/postgres" ;;
    pgvector)    echo "docker.io/pgvector/pgvector" ;;
    mssql)       echo "mcr.microsoft.com/mssql/server" ;;
    oracle)      echo "ghcr.io/oracle/adb-free" ;;
    mongodb)     echo "docker.io/library/mongo" ;;
    redis)       echo "docker.io/library/redis" ;;
    clickhouse)  echo "docker.io/clickhouse/clickhouse-server" ;;
    cockroach)   echo "docker.io/cockroachdb/cockroach" ;;
    snowflake)   echo "ghcr.io/nnnkkk7/snowflake-emulator" ;;
    db2)         echo "icr.io/db2_community/db2" ;;
    databricks)  echo "docker.io/apache/spark" ;;
    *)           echo "spindb/${engine}" ;;
  esac
}

# ------------------------------------------------------------------------------
# Curated Verified Catalogs (Offline-First for All 13 Engines)
# ------------------------------------------------------------------------------

get_curated_major_versions() {
  local engine
  engine="$(normalize_engine_name "$1")"
  case "${engine}" in
    postgres)
      echo "17|PostgreSQL 17 (Latest Production Release)"
      echo "16|PostgreSQL 16 (Recommended Enterprise Standard)"
      echo "15|PostgreSQL 15 (Active Production LTS)"
      echo "14|PostgreSQL 14 (Extended Enterprise Support)"
      echo "13|PostgreSQL 13 (Legacy Maintenance Support)"
      echo "12|PostgreSQL 12 (Legacy Maintenance Support)"
      ;;
    mysql)
      echo "8.4|MySQL 8.4 LTS (Long Term Support - Recommended)"
      echo "8.0|MySQL 8.0 GA (Widely Deployed Enterprise Standard)"
      echo "9.1|MySQL 9.1 Innovation Release"
      echo "5.7|MySQL 5.7 Legacy Release"
      ;;
    mariadb)
      echo "11.4|MariaDB 11.4 LTS (Recommended Long Term Support)"
      echo "10.11|MariaDB 10.11 LTS (Enterprise Standard)"
      echo "10.6|MariaDB 10.6 LTS (Extended Support)"
      echo "11.6|MariaDB 11.6 Short-Term Rolling Release"
      ;;
    pgvector)
      echo "pg17|PostgreSQL 17 with pgvector 0.8.0 AI Embeddings"
      echo "pg16|PostgreSQL 16 with pgvector 0.7.4 (Default Standard)"
      echo "pg15|PostgreSQL 15 with pgvector AI Embeddings"
      echo "pg14|PostgreSQL 14 with pgvector AI Embeddings"
      ;;
    mssql)
      echo "2022-latest|Microsoft SQL Server 2022 (Default Developer Edition)"
      echo "2019-latest|Microsoft SQL Server 2019 CU Release"
      echo "2017-latest|Microsoft SQL Server 2017 Maintenance Release"
      ;;
    mongodb)
      echo "8.0|MongoDB 8.0 (Latest Major Release)"
      echo "7.0|MongoDB 7.0 (Recommended Production Standard)"
      echo "6.0|MongoDB 6.0 (Enterprise LTS Support)"
      echo "5.0|MongoDB 5.0 (Extended Maintenance Support)"
      ;;
    redis)
      echo "7-alpine|Redis 7 Alpine (Default Ultra-Lightweight Cache)"
      echo "7.4|Redis 7.4 Standard Production Release"
      echo "7.2|Redis 7.2 Extended Production Support"
      echo "6-alpine|Redis 6 Alpine Legacy Cache"
      ;;
    clickhouse)
      echo "24.8|ClickHouse 24.8 (Production Stable Release)"
      echo "24.3-lts|ClickHouse 24.3 LTS (Long Term Support Standard)"
      echo "23.8-lts|ClickHouse 23.8 LTS (Extended Support Release)"
      ;;
    cockroach)
      echo "v24.2.0|CockroachDB v24.2 Distributed SQL"
      echo "v24.1.0|CockroachDB v24.1 Production Release"
      echo "v23.2.0|CockroachDB v23.2 Extended Support"
      ;;
    oracle)
      echo "latest|Oracle Autonomous Database Free (Latest)"
      echo "23ai|Oracle Database 23ai Free"
      echo "23.4-free|Oracle Database 23.4 Free Developer Release"
      ;;
    db2)
      echo "11.5.9.0|IBM DB2 Enterprise Developer-C Edition 11.5.9.0"
      echo "11.5.8.0|IBM DB2 Enterprise Developer-C Edition 11.5.8.0"
      echo "latest|IBM DB2 Community Edition (Latest)"
      ;;
    snowflake)
      echo "latest|Snowflake Local Emulator (DuckDB-backed Execution Engine)"
      ;;
    databricks)
      echo "3.5.3|Apache Spark 3.5.3 with Delta Lake (Default)"
      echo "3.5.0|Apache Spark 3.5.0 with Delta Lake"
      echo "3.4.1|Apache Spark 3.4.1 with Delta Lake"
      ;;
  esac
}

get_curated_subversions() {
  local engine
  engine="$(normalize_engine_name "$1")"
  case "${engine}" in
    postgres)
      echo "17.1, 17.0"
      echo "16.6, 16.5, 16.4, 16.3, 16.2, 16.1, 16.0"
      echo "15.10, 15.9, 15.8, 15.7, 15.6, 15.5, 15.4, 15.3, 15.2, 15.1, 15.0"
      echo "14.15, 14.14, 14.10, 14.5, 14.1"
      echo "13.18, 13.14, 13.10"
      echo "17-alpine, 16-alpine, 15-alpine, 14-alpine, 13-alpine (Lightweight)"
      ;;
    mysql)
      echo "8.4.3, 8.4.2, 8.4.1, 8.4.0"
      echo "8.0.40, 8.0.39, 8.0.36, 8.0.35, 8.0.34, 8.0.33, 8.0.32"
      echo "9.1.0, 9.0.1"
      echo "5.7.44, 5.7.43"
      ;;
    mariadb)
      echo "11.4.4, 11.4.3, 11.4.2"
      echo "10.11.10, 10.11.9, 10.11.8, 10.11.7"
      echo "10.6.20, 10.6.19, 10.6.18"
      ;;
    pgvector)
      echo "pg17-v0.8.0, pg17"
      echo "pg16-v0.8.0, pg16-v0.7.4, pg16"
      echo "pg15-v0.8.0, pg15-v0.7.4, pg15"
      echo "pg14-v0.8.0, pg14-v0.7.4, pg14"
      ;;
    mssql)
      echo "2022-CU16-ubuntu-22.04, 2022-CU15-ubuntu-22.04, 2022-CU14-ubuntu-22.04"
      echo "2019-CU28-ubuntu-20.04, 2019-CU27-ubuntu-20.04"
      ;;
    mongodb)
      echo "8.0.3, 8.0.1, 8.0.0"
      echo "7.0.15, 7.0.14, 7.0.12, 7.0.8, 7.0.5"
      echo "6.0.19, 6.0.18, 6.0.16, 6.0.14, 6.0.12"
      echo "5.0.29, 5.0.28, 5.0.26"
      ;;
    redis)
      echo "7.4.1, 7.4.0"
      echo "7.2.6, 7.2.5, 7.2.4, 7.2.3, 7.2-alpine"
      echo "7.0.15, 7.0.14, 7.0.12, 7.0-alpine"
      echo "6.2.16, 6.2.14, 6.2-alpine"
      ;;
    clickhouse)
      echo "24.8.4.13, 24.8.3, 24.8.2"
      echo "24.3.12.75-lts, 24.3.8-lts, 24.3.6-lts"
      echo "23.8.16.41-lts, 23.8.12-lts, 23.8.9-lts"
      ;;
    cockroach)
      echo "v24.2.3, v24.2.0"
      echo "v24.1.5, v24.1.4, v24.1.0"
      echo "v23.2.12, v23.2.8, v23.2.0"
      ;;
    oracle)
      echo "23.4-free, 23.3-free, 23ai"
      ;;
    db2)
      echo "11.5.9.0, 11.5.8.0, 11.5.7.0"
      ;;
    snowflake)
      echo "latest, 0.1.0"
      ;;
    databricks)
      echo "3.5.3-scala2.12-java17-ubuntu, 3.5.3"
      echo "3.5.0-scala2.12-java11-ubuntu, 3.5.0"
      echo "3.4.1-scala2.12-java11-ubuntu, 3.4.1"
      ;;
  esac
}

get_curated_subversions_for_major() {
  local engine="$1"
  local major="$2"
  case "${engine}:${major}" in
    postgres:17) echo "17.1, 17.0, 17-alpine, 17" ;;
    postgres:16) echo "16.6, 16.5, 16.4, 16.3, 16.2, 16.1, 16.0, 16-alpine, 16" ;;
    postgres:15) echo "15.10, 15.9, 15.8, 15.7, 15.6, 15.5, 15.4, 15.3, 15.2, 15.1, 15.0, 15-alpine, 15" ;;
    postgres:14) echo "14.15, 14.14, 14.10, 14.5, 14.1, 14-alpine, 14" ;;
    postgres:13) echo "13.18, 13.14, 13.10, 13-alpine, 13" ;;
    postgres:12) echo "12.20, 12.18, 12.16, 12" ;;

    mysql:8.4)  echo "8.4.3, 8.4.2, 8.4.1, 8.4.0, 8.4" ;;
    mysql:8.0)  echo "8.0.40, 8.0.39, 8.0.36, 8.0.35, 8.0.34, 8.0.33, 8.0.32, 8.0" ;;
    mysql:9.1)  echo "9.1.0, 9.0.1, 9.1" ;;
    mysql:5.7)  echo "5.7.44, 5.7.43, 5.7" ;;

    mariadb:11.4)  echo "11.4.4, 11.4.3, 11.4.2, 11.4" ;;
    mariadb:10.11) echo "10.11.10, 10.11.9, 10.11.8, 10.11.7, 10.11" ;;
    mariadb:10.6)  echo "10.6.20, 10.6.19, 10.6.18, 10.6" ;;
    mariadb:11.6)  echo "11.6.2, 11.6.1, 11.6" ;;

    pgvector:pg17) echo "pg17-v0.8.0, pg17" ;;
    pgvector:pg16) echo "pg16-v0.8.0, pg16-v0.7.4, pg16" ;;
    pgvector:pg15) echo "pg15-v0.8.0, pg15-v0.7.4, pg15" ;;
    pgvector:pg14) echo "pg14-v0.8.0, pg14-v0.7.4, pg14" ;;

    mssql:2022-latest) echo "2022-CU16-ubuntu-22.04, 2022-CU15-ubuntu-22.04, 2022-CU14-ubuntu-22.04, 2022-latest" ;;
    mssql:2019-latest) echo "2019-CU28-ubuntu-20.04, 2019-CU27-ubuntu-20.04, 2019-latest" ;;
    mssql:2017-latest) echo "2017-CU31-ubuntu-16.04, 2017-latest" ;;

    mongodb:8.0) echo "8.0.3, 8.0.1, 8.0.0, 8.0" ;;
    mongodb:7.0) echo "7.0.15, 7.0.14, 7.0.12, 7.0.8, 7.0.5, 7.0" ;;
    mongodb:6.0) echo "6.0.19, 6.0.18, 6.0.16, 6.0.14, 6.0.12, 6.0" ;;
    mongodb:5.0) echo "5.0.29, 5.0.28, 5.0.26, 5.0" ;;

    redis:7-alpine) echo "7-alpine, 7.4-alpine, 7.2-alpine, 7.0-alpine" ;;
    redis:7.4)      echo "7.4.1, 7.4.0, 7.4" ;;
    redis:7.2)      echo "7.2.6, 7.2.5, 7.2.4, 7.2.3, 7.2, 7.2-alpine" ;;
    redis:6-alpine) echo "6.2.16, 6.2.14, 6.2-alpine, 6-alpine" ;;

    clickhouse:24.8)     echo "24.8.4.13, 24.8.3, 24.8.2, 24.8" ;;
    clickhouse:24.3-lts) echo "24.3.12.75-lts, 24.3.8-lts, 24.3.6-lts, 24.3-lts" ;;
    clickhouse:23.8-lts) echo "23.8.16.41-lts, 23.8.12-lts, 23.8.9-lts, 23.8-lts" ;;

    cockroach:v24.2.0) echo "v24.2.3, v24.2.0" ;;
    cockroach:v24.1.0) echo "v24.1.5, v24.1.4, v24.1.0" ;;
    cockroach:v23.2.0) echo "v23.2.12, v23.2.8, v23.2.0" ;;

    oracle:latest)    echo "latest" ;;
    oracle:23ai)      echo "23ai" ;;
    oracle:23.4-free) echo "23.4-free, 23.3-free" ;;

    db2:11.5.9.0) echo "11.5.9.0, 11.5.8.0, 11.5.7.0" ;;
    db2:11.5.8.0) echo "11.5.8.0, 11.5.7.0" ;;
    db2:latest)   echo "latest" ;;

    snowflake:latest) echo "latest, 0.1.0" ;;

    databricks:3.5.3) echo "3.5.3-scala2.12-java17-ubuntu, 3.5.3" ;;
    databricks:3.5.0) echo "3.5.0-scala2.12-java11-ubuntu, 3.5.0" ;;
    databricks:3.4.1) echo "3.4.1-scala2.12-java11-ubuntu, 3.4.1" ;;
    *) echo "${major}, latest" ;;
  esac
}

# ------------------------------------------------------------------------------
# Local Image Inspector (Docker / Podman)
# ------------------------------------------------------------------------------

get_locally_cached_images() {
  local engine="$1"
  local norm
  norm="$(normalize_engine_name "${engine}")"
  local repo
  repo="$(get_base_image_repo_for_engine "${norm}")"

  # Find available runtime
  local crun=""
  if [[ -n "${CONTAINER_ENGINE:-}" ]]; then
    crun="${CONTAINER_ENGINE}"
  elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    crun="podman"
  elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    crun="docker"
  else
    return 0
  fi

  # Match repo name patterns, e.g. postgres, library/postgres, docker.io/library/postgres
  local short_name="${norm}"
  case "${norm}" in
    mongodb) short_name="(mongo|mongodb)" ;;
    mssql) short_name="(mssql/server|mssql)" ;;
    clickhouse) short_name="(clickhouse-server|clickhouse)" ;;
    snowflake) short_name="(snowflake-emulator|snowflake)" ;;
    databricks) short_name="(spark|databricks)" ;;
    oracle) short_name="(adb-free|oracle)" ;;
    *) short_name="${norm}" ;;
  esac

  # Query local images: repository, tag, size
  "${crun}" images --format '{{.Repository}}:{{.Tag}} ({{.Size}})' 2>/dev/null | \
    grep -E "(^|/)${short_name}:" | grep -v '<none>' || true
}

# ------------------------------------------------------------------------------
# Remote Registry Query Engine (Docker Registry V2)
# ------------------------------------------------------------------------------

fetch_remote_registry_tags() {
  local engine="$1"
  local timeout_seconds="${2:-2}"
  local norm
  norm="$(normalize_engine_name "${engine}")"

  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  local url=""
  case "${norm}" in
    mysql|mariadb|postgres|mongodb|redis)
      url="https://registry.hub.docker.com/v2/repositories/library/${norm}/tags?page_size=100"
      ;;
    pgvector)
      url="https://registry.hub.docker.com/v2/repositories/pgvector/pgvector/tags?page_size=100"
      ;;
    clickhouse)
      url="https://registry.hub.docker.com/v2/repositories/clickhouse/clickhouse-server/tags?page_size=100"
      ;;
    cockroach)
      url="https://registry.hub.docker.com/v2/repositories/cockroachdb/cockroach/tags?page_size=100"
      ;;
    databricks)
      url="https://registry.hub.docker.com/v2/repositories/apache/spark/tags?page_size=100"
      ;;
    mssql)
      url="https://mcr.microsoft.com/v2/mssql/server/tags/list"
      ;;
    *)
      return 1
      ;;
  esac

  local json_resp
  json_resp="$(curl -s -f --connect-timeout "${timeout_seconds}" --max-time "$((timeout_seconds + 3))" "${url}" 2>/dev/null || echo '')"
  if [[ -z "${json_resp}" ]]; then
    return 1
  fi

  # Parse tag names from JSON response
  if [[ "${norm}" == "mssql" ]]; then
    echo "${json_resp}" | grep -o '"tags":\[[^]]*\]' | grep -o '"[^",]*"' | tr -d '"' | grep -v 'tags' || true
  else
    echo "${json_resp}" | grep -o '"name": *"[^"]*"' | cut -d'"' -f4 || true
  fi
}

# ------------------------------------------------------------------------------
# Main Discovery & Output Controller
# ------------------------------------------------------------------------------

list_engine_versions() {
  local raw_engine="$1"
  local filter="${2:-}"
  local force_refresh="${3:-false}"
  local offline_mode="${4:-false}"

  local engine
  engine="$(normalize_engine_name "${raw_engine}")"
  local repo
  repo="$(get_base_image_repo_for_engine "${engine}")"
  local ttl_sec
  ttl_sec="$(get_cache_ttl_seconds)"
  local ttl_hours=$((ttl_sec / 3600))
  local cache_file
  cache_file="$(get_cache_file_for_engine "${engine}")"

  printf "\n"
  printf "${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n"
  printf "  ${CLR_BOLD}SPINDB DATABASE IMAGE & VARIANT CATALOG: %s (%s)${CLR_RESET}\n" "${raw_engine^^}" "${engine}"
  printf "${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n"
  printf "  * ${CLR_BOLD}Base Image Repository:${CLR_RESET} %s\n" "${repo}"

  # 1. Check & Report Local Engine Cache
  local local_images
  local_images="$(get_locally_cached_images "${engine}")"
  printf "  * ${CLR_BOLD}Locally Downloaded Images (Instant Launch):${CLR_RESET}\n"
  if [[ -n "${local_images}" ]]; then
    while IFS= read -r img_line; do
      printf "    ${CLR_GREEN}[CACHED]${CLR_RESET} %s\n" "${img_line}"
    done <<< "${local_images}"
  else
    printf "    ${CLR_YELLOW}(None currently cached locally. First run will pull automatically)${CLR_RESET}\n"
  fi

  # 2. TTL Cache Invalidation & Remote Registry Query
  local cache_status="Active"
  local cache_age
  cache_age="$(get_cache_age_human "${cache_file}")"
  local remote_tags=()

  if [[ "${offline_mode}" == "true" ]]; then
    cache_status="Offline Mode (Using local cache / curated data)"
    if [[ -f "${cache_file}" ]]; then
      mapfile -t remote_tags < <(read_cache_tags "${cache_file}")
    fi
  elif [[ "${force_refresh}" == "true" ]] || ! is_cache_valid "${cache_file}" "${ttl_sec}"; then
    # Cache is either missing, expired (> 12-24h), or --refresh requested
    log_info "Updating version metadata from registry (TTL: ${ttl_hours}h)..."
    local fetched
    fetched="$(fetch_remote_registry_tags "${engine}" 2 2>/dev/null || echo '')"
    if [[ -n "${fetched}" ]]; then
      mapfile -t remote_tags <<< "${fetched}"
      write_cache_tags "${cache_file}" "${engine}" "${remote_tags[@]}"
      cache_status="Refreshed & Valid for ${ttl_hours}h (Just now)"
    elif [[ -f "${cache_file}" ]]; then
      cache_status="Registry unreachable; using existing cache (${cache_age})"
      mapfile -t remote_tags < <(read_cache_tags "${cache_file}")
    else
      cache_status="Registry unreachable; using built-in curated catalog"
    fi
  else
    cache_status="Fresh Local Cache (${cache_age}, valid for ${ttl_hours}h)"
    mapfile -t remote_tags < <(read_cache_tags "${cache_file}")
  fi

  printf "  * ${CLR_BOLD}Cache Status:${CLR_RESET}          %s\n" "${cache_status}"
  printf -- "-------------------------------------------------------------------------------\n"

  # 3. Recommended & Curated Major Families
  printf "  ${CLR_BOLD}Recommended & LTS Major Release Families:${CLR_RESET}\n"
  while IFS='|' read -r vtag vdesc; do
    if [[ -n "${vtag}" ]]; then
      if [[ -z "${filter}" || "${vtag}" == *"${filter}"* ]]; then
        printf "    * ${CLR_BOLD}%-16s${CLR_RESET} %s\n" "${vtag}" "${vdesc}"
      fi
    fi
  done < <(get_curated_major_versions "${engine}")

  # 4. Curated Sub-versions & Specific Variants
  printf "\n  ${CLR_BOLD}Available Sub-Versions & Micro-Releases:${CLR_RESET}\n"
  while IFS= read -r subline; do
    if [[ -n "${subline}" ]]; then
      if [[ -z "${filter}" || "${subline}" == *"${filter}"* ]]; then
        printf "    * %s\n" "${subline}"
      fi
    fi
  done < <(get_curated_subversions "${engine}")

  # 5. Filtered Dynamic Registry Tags (if user specified a filter)
  if [[ -n "${filter}" && ${#remote_tags[@]} -gt 0 ]]; then
    printf "\n  ${CLR_BOLD}Remote Registry Matches for '${filter}':${CLR_RESET}\n"
    local count=0
    for rtag in "${remote_tags[@]}"; do
      if [[ "${rtag}" == *"${filter}"* ]]; then
        printf "    - %s\n" "${rtag}"
        count=$((count + 1))
        if [[ ${count} -ge 20 ]]; then
          printf "    - ... (additional matches omitted)\n"
          break
        fi
      fi
    done
    if [[ ${count} -eq 0 ]]; then
      printf "    ${CLR_YELLOW}(No additional remote registry tags matched '${filter}')${CLR_RESET}\n"
    fi
  fi

  # 6. Quick Start & Multi-Variant Usage Instructions
  printf "\n  ${CLR_BOLD}Quick-Start & Multi-Variant Launch Commands:${CLR_RESET}\n"
  case "${engine}" in
    postgres)
      printf "    # Launch PostgreSQL 16 on default port 5432 (Name: postgres-16-5432):\n"
      printf "    ${CLR_GREEN}spinctl -t postgres -v 16${CLR_RESET}\n\n"
      printf "    # Launch PostgreSQL 16.1 concurrently (Name: postgres-16.1-5433):\n"
      printf "    ${CLR_GREEN}spinctl -t postgres -v 16.1${CLR_RESET}\n\n"
      printf "    # Launch PostgreSQL 15 on custom port 5435 (Name: postgres-15-5435):\n"
      printf "    ${CLR_GREEN}spinctl -t postgres -v 15 -p 5435${CLR_RESET}\n\n"
      printf "    # Launch PostgreSQL 14 with custom name:\n"
      printf "    ${CLR_GREEN}spinctl -t postgres -v 14 -n dev-pg14${CLR_RESET}\n"
      ;;
    mysql)
      printf "    spinctl -t mysql -v 8.4\n"
      printf "    spinctl -t mysql -v 8.0.40\n"
      printf "    spinctl -t mysql -v 5.7 -p 3307\n"
      ;;
    redis)
      printf "    spinctl -t redis -v 7-alpine\n"
      printf "    spinctl -t redis -v 7.2\n"
      printf "    spinctl -t redis -v 6-alpine -p 6380\n"
      ;;
    *)
      printf "    spinctl -t %s -v <version>\n" "${engine}"
      printf "    spinctl -t %s -v <version> -p <port>\n" "${engine}"
      ;;
  esac

  printf "${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n\n"
}

list_all_supported_engines_matrix() {
  local force_refresh="${1:-false}"
  local offline_mode="${2:-false}"

  printf "\n"
  printf "${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n"
  printf "  ${CLR_BOLD}SPINDB SUPPORTED DATABASE ENGINES & RECOMMENDED VERSIONS${CLR_RESET}\n"
  printf "${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n\n"

  printf "  %-14s %-22s %-12s %s\n" "ENGINE KEY" "DATABASE NAME" "DEFAULT PORT" "RECOMMENDED VERSIONS"
  printf "  %-14s %-22s %-12s %s\n" "----------" "-------------" "------------" "--------------------"
  printf "  %-14s %-22s %-12s %s\n" "postgres" "PostgreSQL" "5432" "17, 16 (default), 15, 14, 16.1, alpine"
  printf "  %-14s %-22s %-12s %s\n" "mysql" "MySQL Community" "3306" "8.4 LTS (default), 8.0, 9.1, 5.7"
  printf "  %-14s %-22s %-12s %s\n" "mariadb" "MariaDB Server" "3306" "11.4 LTS (default), 10.11 LTS, 10.6"
  printf "  %-14s %-22s %-12s %s\n" "pgvector" "PostgreSQL + pgvector" "5432" "pg17, pg16 (default), pg15, pg14"
  printf "  %-14s %-22s %-12s %s\n" "mssql" "Microsoft SQL Server" "1433" "2022-latest (default), 2019-latest"
  printf "  %-14s %-22s %-12s %s\n" "mongodb" "MongoDB Document NoSQL" "27017" "8.0, 7.0 (default), 6.0, 5.0"
  printf "  %-14s %-22s %-12s %s\n" "redis" "Redis / Valkey Cache" "6379" "7-alpine (default), 7.4, 7.2, 6-alpine"
  printf "  %-14s %-22s %-12s %s\n" "clickhouse" "ClickHouse Columnar" "8123" "24.8 (default), 24.3-lts, 23.8-lts"
  printf "  %-14s %-22s %-12s %s\n" "cockroach" "CockroachDB SQL" "26257" "v24.2.0, v24.1.0, v23.2.0"
  printf "  %-14s %-22s %-12s %s\n" "oracle" "Oracle ADB Free" "1521" "latest (default), 23ai, 23.4-free"
  printf "  %-14s %-22s %-12s %s\n" "db2" "IBM DB2 Enterprise" "50000" "11.5.9.0, 11.5.8.0, latest"
  printf "  %-14s %-22s %-12s %s\n" "snowflake" "Snowflake Local Emu" "8080" "latest"
  printf "  %-14s %-22s %-12s %s\n" "databricks" "Databricks Spark+Delta" "10000" "3.5.3 (default), 3.5.0, 3.4.1"

  printf "\n${CLR_BOLD}To inspect complete versions, sub-versions, and cached images for any engine:${CLR_RESET}\n"
  printf "  spinctl versions <engine>             # e.g. spinctl versions postgres\n"
  printf "  spinctl versions <engine> <filter>    # e.g. spinctl versions postgres 16.1\n"
  printf "  spinctl versions <engine> --refresh   # Force refresh registry cache\n\n"
}

get_engine_versions_json() {
  local engine="${1:-postgres}"
  local norm
  norm="$(normalize_engine_name "${engine}")"

  local default_major="latest"
  local default_sub="latest"
  case "${norm}" in
    postgres)    default_major="16"; default_sub="16" ;;
    mysql)       default_major="8.4"; default_sub="8.4" ;;
    mariadb)     default_major="11.4"; default_sub="11.4" ;;
    pgvector)    default_major="pg16"; default_sub="pg16" ;;
    mssql)       default_major="2022-latest"; default_sub="2022-latest" ;;
    mongodb)     default_major="7.0"; default_sub="7.0" ;;
    redis)       default_major="7-alpine"; default_sub="7-alpine" ;;
    clickhouse)  default_major="24.8"; default_sub="24.8" ;;
    cockroach)   default_major="v24.2.0"; default_sub="v24.2.0" ;;
    oracle)      default_major="latest"; default_sub="latest" ;;
    db2)         default_major="11.5.9.0"; default_sub="11.5.9.0" ;;
    snowflake)   default_major="latest"; default_sub="latest" ;;
    databricks)  default_major="3.5.3"; default_sub="3.5.3" ;;
  esac

  local local_images
  local_images="$(get_locally_cached_images "${norm}")"

  local cached_json="[]"
  local cached_tags=()
  if [[ -n "${local_images}" ]]; then
    local cached_items=()
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      local tag
      tag="$(echo "${line}" | sed -E 's/^.*:([^ ]+) *\((.*)\)$/\1/')"
      local size
      size="$(echo "${line}" | sed -E 's/^.*:([^ ]+) *\((.*)\)$/\2/')"
      if [[ -n "${tag}" ]]; then
        cached_items+=("{\"tag\":\"${tag}\",\"size\":\"${size}\"}")
        cached_tags+=("${tag}")
      fi
    done <<< "${local_images}"
    if [[ ${#cached_items[@]} -gt 0 ]]; then
      local old_ifs="$IFS"
      IFS=','
      cached_json="[${cached_items[*]}]"
      IFS="$old_ifs"
    fi
  fi

  # Check if remote cache file exists
  local cache_file
  cache_file="$(get_cache_file_for_engine "${norm}")"
  local remote_tags=()
  if [[ -f "${cache_file}" ]]; then
    mapfile -t remote_tags < <(read_cache_tags "${cache_file}")
  fi

  local major_items=()
  local major_keys=()
  while IFS='|' read -r vtag vdesc; do
    [[ -z "${vtag}" ]] && continue
    vdesc="${vdesc//\"/\\\"}"
    major_items+=("{\"id\":\"${vtag}\",\"label\":\"${vdesc}\"}")
    major_keys+=("${vtag}")
  done < <(get_curated_major_versions "${norm}")

  if [[ ${#major_items[@]} -eq 0 ]]; then
    major_items+=("{\"id\":\"latest\",\"label\":\"${norm} (latest)\"}")
    major_keys+=("latest")
  fi

  local sub_entries=()
  for mkey in "${major_keys[@]}"; do
    local sub_csv
    sub_csv="$(get_curated_subversions_for_major "${norm}" "${mkey}")"
    local raw_subs=()
    IFS=',' read -ra ADDR <<< "${sub_csv}"
    for s in "${ADDR[@]}"; do
      s="$(echo "${s}" | xargs)"
      [[ -n "${s}" ]] && raw_subs+=("${s}")
    done

    # Add matching cached remote tags if available (limit 5)
    local remote_count=0
    for rtag in "${remote_tags[@]}"; do
      if [[ "${rtag}" == "${mkey}"* ]]; then
        raw_subs+=("${rtag}")
        remote_count=$((remote_count + 1))
        [[ ${remote_count} -ge 5 ]] && break
      fi
    done

    # Build unique subversion list preserving order
    local unique_subs=()
    for s in "${raw_subs[@]}"; do
      local exists=false
      for u in "${unique_subs[@]}"; do
        if [[ "${u}" == "${s}" ]]; then
          exists=true
          break
        fi
      done
      if [[ "${exists}" == "false" ]]; then
        unique_subs+=("${s}")
      fi
    done

    local sub_json_items=()
    for s in "${unique_subs[@]}"; do
      sub_json_items+=("\"${s}\"")
    done

    local old_ifs="$IFS"
    IFS=','
    sub_entries+=("\"${mkey}\":[${sub_json_items[*]}]")
    IFS="$old_ifs"
  done

  local old_ifs="$IFS"
  IFS=','
  local majors_joined="${major_items[*]}"
  local subs_joined="${sub_entries[*]}"
  IFS="$old_ifs"

  printf '{\n'
  printf '  "status": "success",\n'
  printf '  "engine": "%s",\n' "${norm}"
  printf '  "defaultMajor": "%s",\n' "${default_major}"
  printf '  "defaultSub": "%s",\n' "${default_sub}"
  printf '  "majorVersions": [%s],\n' "${majors_joined}"
  printf '  "subVersions": {%s},\n' "${subs_joined}"
  printf '  "localCached": %s\n' "${cached_json}"
  printf '}\n'
}

