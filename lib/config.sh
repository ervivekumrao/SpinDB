#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# lib/config.sh - Safe Configuration & Property Management
# ==============================================================================

[[ -n "${_LIB_CONFIG_LOADED:-}" ]] && return 0
_LIB_CONFIG_LOADED=1

find_properties_file() {
  local candidates=(
    "${PROJECT_ROOT}/Database.properties.local"
    "${PROJECT_ROOT}/database.properties.local"
    "${PROJECT_ROOT}/config/Database.properties.local"
    "${PROJECT_ROOT}/config/database.properties.local"
    "${PROJECT_ROOT}/config/database.env"
    "${PROJECT_ROOT}/Database.properties"
    "${PROJECT_ROOT}/database.properties"
    "${PROJECT_ROOT}/config/Database.properties"
    "${PROJECT_ROOT}/config/database.properties"
  )

  for file in "${candidates[@]}"; do
    if [[ -f "${file}" ]]; then
      echo "${file}"
      return 0
    fi
  done
  return 1
}

get_property() {
  local key="$1"
  local prop_file="${PROPERTIES_FILE:-$(find_properties_file)}"

  if [[ ! -f "${prop_file}" ]]; then
    log_error "Configuration properties file not found: ${prop_file}"
    return 1
  fi

  # Line-anchored key extraction, preserving "=" inside values, stripping Windows \r
  awk -F '=' -v k="${key}" '$1 == k { sub(/^[^=]*=/, ""); gsub(/\r/, ""); print; exit }' "${prop_file}"
}
