#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/test_harness.sh - Lightweight Bash Unit Testing Assertion Library
# ==============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_GREEN="\033[32m"
CLR_RED="\033[31m"
CLR_CYAN="\033[36m"

test_suite_start() {
  printf "\n${CLR_BOLD}${CLR_CYAN}>>> Running Test Suite: %s${CLR_RESET}\n" "$1"
}

run_test() {
  local test_name="$1"
  local test_fn="$2"
  ((TESTS_RUN+=1))

  printf "  [TEST] %-55s " "${test_name}..."
  
  # Run in subshell so test environment variables or exits don't contaminate
  if ( ${test_fn} ) >/tmp/test_output.log 2>&1; then
    printf "${CLR_BOLD}${CLR_GREEN}[PASS]${CLR_RESET}\n"
    ((TESTS_PASSED+=1))
  else
    printf "${CLR_BOLD}${CLR_RED}[FAIL]${CLR_RESET}\n"
    ((TESTS_FAILED+=1))
    printf "    ${CLR_RED}--- Failure Output ---${CLR_RESET}\n"
    sed 's/^/    /' /tmp/test_output.log
    printf "    ${CLR_RED}----------------------${CLR_RESET}\n"
  fi
  rm -f /tmp/test_output.log
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-Assertion failed}"

  if [[ "${expected}" != "${actual}" ]]; then
    printf "Expected: '%s'\nActual:   '%s'\nMessage:  %s\n" "${expected}" "${actual}" "${msg}" >&2
    return 1
  fi
  return 0
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-Assertion failed}"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    printf "Expected to contain: '%s'\nActual text:         '%s'\nMessage:             %s\n" "${needle}" "${haystack}" "${msg}" >&2
    return 1
  fi
  return 0
}

assert_file_exists() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    printf "Expected file to exist: '%s'\n" "${file}" >&2
    return 1
  fi
  return 0
}

assert_dir_exists() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    printf "Expected directory to exist: '%s'\n" "${dir}" >&2
    return 1
  fi
  return 0
}

test_suite_end() {
  printf "\n${CLR_BOLD}Suite Summary: %d Run, ${CLR_GREEN}%d Passed${CLR_RESET}, ${CLR_RED}%d Failed${CLR_RESET}\n\n" \
    "${TESTS_RUN}" "${TESTS_PASSED}" "${TESTS_FAILED}"
  if [[ "${TESTS_FAILED}" -gt 0 ]]; then
    return 1
  fi
  return 0
}
