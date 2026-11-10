#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# lib/studio.sh - SpinDB Web Studio Launcher (Browser-based SQL Client UI)
# ==============================================================================

[[ -n "${_LIB_STUDIO_LOADED:-}" ]] && return 0
_LIB_STUDIO_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=lib/logger.sh
source "${PROJECT_ROOT}/lib/logger.sh"

launch_studio() {
  local port="8080"
  local target=""
  local auto_open=true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--port)
        port="$2"
        shift 2
        ;;
      -n|--target|--container)
        target="$2"
        shift 2
        ;;
      --no-browser|--no-open)
        auto_open=false
        shift 1
        ;;
      -h|--help)
        echo "Usage: spinctl studio [-p PORT] [-n CONTAINER_NAME] [--no-browser]"
        echo ""
        echo "Options:"
        echo "  -p, --port <port>       Web Studio HTTP port (Default: 8080)"
        echo "  -n, --target <name>     Pre-select running container name"
        echo "  --no-browser            Do not automatically open default web browser"
        echo "  -h, --help              Show this help message"
        exit 0
        ;;
      *)
        if [[ -z "${target}" && "$1" =~ ^[a-zA-Z0-9_-]+$ && ! "$1" =~ ^[0-9]+$ ]]; then
          target="$1"
        elif [[ "$1" =~ ^[0-9]+$ ]]; then
          port="$1"
        fi
        shift 1
        ;;
    esac
  done

  # Verify Python 3 is installed
  local py_cmd=""
  if command -v python3 >/dev/null 2>&1; then
    py_cmd="python3"
  elif command -v python >/dev/null 2>&1; then
    py_cmd="python"
  else
    log_error "Python 3 is required to run SpinDB Web Studio, but was not found in PATH."
    exit 1
  fi

  local py_args=("${PROJECT_ROOT}/lib/studio.py" "--port" "${port}")
  if [[ -n "${target}" ]]; then
    py_args+=("--target" "${target}")
  fi
  if [[ "${auto_open}" == true ]]; then
    py_args+=("--open")
  fi

  log_info "Launching SpinDB Web Studio on port ${port}..."
  exec "${py_cmd}" "${py_args[@]}"
}
