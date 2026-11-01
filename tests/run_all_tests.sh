#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/run_all_tests.sh - Master Test Orchestrator & Execution Suite
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

START_TIME=$(date +%s)
TOTAL_FAILURES=0

CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_CYAN="\033[36m"
CLR_GREEN="\033[32m"
CLR_RED="\033[31m"

printf "${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n"
printf "${CLR_BOLD}${CLR_CYAN}               SPINDB (SPINCTL) COMPREHENSIVE TEST SUITE                       ${CLR_RESET}\n"
printf "${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n"

chmod +x "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}"/unit/*.sh "${SCRIPT_DIR}"/integration/*.sh 2>/dev/null || true

# 1. Lint and Static Syntax
if ! "${SCRIPT_DIR}/lint.sh"; then
  ((TOTAL_FAILURES++))
fi

# 2. Unit Tests
for test_script in "${SCRIPT_DIR}"/unit/test_*.sh; do
  if ! "${test_script}"; then
    ((TOTAL_FAILURES++))
  fi
done

# 3. Smoke Tests
if ! "${SCRIPT_DIR}/smoke_test.sh"; then
  ((TOTAL_FAILURES++))
fi

# 4. Enterprise Live Production Tests
for test_script in "${SCRIPT_DIR}"/integration/*.sh; do
  if [[ -f "${test_script}" ]]; then
    if ! "${test_script}"; then
      ((TOTAL_FAILURES++))
    fi
  fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

printf "\n${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n"
if [[ "${TOTAL_FAILURES}" -eq 0 ]]; then
  printf "${CLR_BOLD}${CLR_GREEN}[ALL TESTS PASSED]${CLR_RESET} Entire suite finished in %d seconds.\n" "${ELAPSED}"
  printf "${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n"
  exit 0
else
  printf "${CLR_BOLD}${CLR_RED}[SUITE FAILED]${CLR_RESET} %d test suites failed! Finished in %d seconds.\n" "${TOTAL_FAILURES}" "${ELAPSED}"
  printf "${CLR_BOLD}${CLR_CYAN}===============================================================================${CLR_RESET}\n"
  exit 1
fi
