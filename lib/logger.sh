#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# lib/logger.sh - Standardized Logging & Formatting Subsystem
# ==============================================================================

# Guard against multiple inclusion
[[ -n "${_LIB_LOGGER_LOADED:-}" ]] && return 0
_LIB_LOGGER_LOADED=1

CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_RED="\033[31m"
CLR_GREEN="\033[32m"
CLR_YELLOW="\033[33m"
CLR_BLUE="\033[34m"
CLR_CYAN="\033[36m"
CLR_GRAY="\033[90m"

log_info() {
  printf "${CLR_BOLD}${CLR_BLUE}==>${CLR_RESET} %s\n" "$*"
}

log_success() {
  printf "${CLR_BOLD}${CLR_GREEN}[SUCCESS]${CLR_RESET} %s\n" "$*"
}

log_warn() {
  printf "${CLR_BOLD}${CLR_YELLOW}[WARNING]${CLR_RESET} %s\n" "$*" >&2
}

log_error() {
  printf "${CLR_BOLD}${CLR_RED}[ERROR]${CLR_RESET} %s\n" "$*" >&2
}

log_header() {
  printf "\n${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n"
  printf "${CLR_BOLD}${CLR_CYAN}  %s${CLR_RESET}\n" "$*"
  printf "${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n"
}
