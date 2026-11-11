#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/unit/test_studio.sh - Unit Tests for SpinDB Web Studio & SQL Client UI
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/studio.sh"

test_suite_start "SpinDB Web Studio & SQL Client Subsystem (lib/studio.sh)"

test_help_advertises_studio_subcommands() {
  local help_out
  help_out="$("${PROJECT_ROOT}/bin/spinctl" --help)"
  assert_contains "${help_out}" "studio" "Help missing 'studio'"
  assert_contains "${help_out}" "ui" "Help missing 'ui'"
}

test_studio_cli_help() {
  local studio_help
  studio_help="$("${PROJECT_ROOT}/bin/spinctl" studio --help)"
  assert_contains "${studio_help}" "--port" "Studio help missing '--port'"
  assert_contains "${studio_help}" "--target" "Studio help missing '--target'"
  assert_contains "${studio_help}" "--no-browser" "Studio help missing '--no-browser'"
}

test_studio_python_driver_catalog() {
  python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/studio')
import server as studio

assert 'postgres' in studio.DRIVER_CATALOG, 'postgres missing from catalog'
assert 'mysql' in studio.DRIVER_CATALOG, 'mysql missing from catalog'
assert 'mariadb' in studio.DRIVER_CATALOG, 'mariadb missing from catalog'
assert 'clickhouse' in studio.DRIVER_CATALOG, 'clickhouse missing from catalog'
assert 'mssql' in studio.DRIVER_CATALOG, 'mssql missing from catalog'
assert 'oracle' in studio.DRIVER_CATALOG, 'oracle missing from catalog'
assert 'mongodb' in studio.DRIVER_CATALOG, 'mongodb missing from catalog'
assert 'redis' in studio.DRIVER_CATALOG, 'redis missing from catalog'
assert 'cockroach' in studio.DRIVER_CATALOG, 'cockroach missing from catalog'
assert 'snowflake' in studio.DRIVER_CATALOG, 'snowflake missing from catalog'
assert 'databricks' in studio.DRIVER_CATALOG, 'databricks missing from catalog'

# Check driver class attributes
pg = studio.DRIVER_CATALOG['postgres']
assert pg['driverClass'] == 'org.postgresql.Driver'
assert pg['fileName'].endswith('.jar')
assert pg['downloadUrl'].startswith('https://repo1.maven.org/')
"
}

test_studio_properties_loading_and_jdbc_template() {
  python3 -c "
import sys
sys.path.insert(0, '${PROJECT_ROOT}/studio')
import server as studio

props = studio.load_properties()
assert 'POSTGRES_JDBC_URL' in props or 'POSTGRES_PORT' in props, 'Properties not loaded'
assert 'MYSQL_JDBC_URL' in props or 'MYSQL_PORT' in props, 'MySQL properties not loaded'
"
}

test_studio_server_smoke_startup_and_api() {
  # Dynamically acquire an available port
  local test_port
  test_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')"
  local py_pid=""
  local log_tmp
  log_tmp="$(mktemp)"

  local server_bin="${PROJECT_ROOT}/studio/server.py"
  if [[ ! -f "${server_bin}" ]]; then
    server_bin="${PROJECT_ROOT}/lib/studio.py"
  fi

  python3 "${server_bin}" --port "${test_port}" >"${log_tmp}" 2>&1 &
  py_pid=$!

  # Clean up process on exit
  trap "kill -9 ${py_pid} 2>/dev/null || true; rm -f ${log_tmp} 2>/dev/null || true" EXIT

  # Wait up to 5s for server to listen
  local ready=0
  for _ in {1..30}; do
    if curl -s "http://127.0.0.1:${test_port}/api/drivers" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.1
  done

  if [[ "${ready}" -eq 0 ]]; then
    printf "Web studio server failed to start within timeout on port %s. Log:\n" "${test_port}" >&2
    cat "${log_tmp}" >&2
    return 1
  fi

  # Test GET / (HTML Page)
  local index_html
  index_html="$(curl -s "http://127.0.0.1:${test_port}/")"
  assert_contains "${index_html}" "SpinDB Web Studio" "Index HTML missing title"
  assert_contains "${index_html}" "JDBC Connection URL" "Index HTML missing JDBC section"
  assert_contains "${index_html}" "SQL Query Runner" "Index HTML missing SQL Query Runner"

  # Test GET /api/containers
  local containers_json
  containers_json="$(curl -s "http://127.0.0.1:${test_port}/api/containers")"
  assert_contains "${containers_json}" '"status": "ok"' "API /api/containers failed"
  assert_contains "${containers_json}" '"containers":' "API /api/containers missing containers key"

  # Test GET /api/drivers
  local drivers_json
  drivers_json="$(curl -s "http://127.0.0.1:${test_port}/api/drivers")"
  assert_contains "${drivers_json}" '"postgres":' "API /api/drivers missing postgres"
  assert_contains "${drivers_json}" '"mysql":' "API /api/drivers missing mysql"

  # Test GET /api/versions
  local versions_json
  versions_json="$(curl -s "http://127.0.0.1:${test_port}/api/versions?engine=postgres")"
  assert_contains "${versions_json}" '"status": "success"' "API /api/versions missing success status"
  assert_contains "${versions_json}" '"defaultMajor": "16"' "API /api/versions missing defaultMajor 16"

  # Test UI features presence in index HTML
  assert_contains "${index_html}" "Table DDL" "Index HTML missing Table DDL tab"
  assert_contains "${index_html}" "Seed Mock Data" "Index HTML missing Seed Mock Data"
  assert_contains "${index_html}" "Code Snippets" "Index HTML missing Code Snippets"
  assert_contains "${index_html}" "SQL Dump" "Index HTML missing SQL Dump"
  assert_contains "${index_html}" "spin-version-loading" "Index HTML missing spin-version-loading spinner"
  assert_contains "${index_html}" "spin-major-version" "Index HTML missing spin-major-version select"
  assert_contains "${index_html}" "spin-sub-version" "Index HTML missing spin-sub-version select"

  # Test GET /api/table-ddl
  local ddl_json
  ddl_json="$(curl -s "http://127.0.0.1:${test_port}/api/table-ddl?table=test&schema=public&engine=postgres")"
  assert_contains "${ddl_json}" '"status": "ok"' "API /api/table-ddl failed"

  # Stop server
  kill -9 "${py_pid}" 2>/dev/null || true
  trap - EXIT
  return 0
}

run_test "CLI Help advertises 'studio' and 'ui' subcommands" test_help_advertises_studio_subcommands
run_test "Studio CLI option routing and --help flag" test_studio_cli_help
run_test "Driver catalog completeness across all supported database engines" test_studio_python_driver_catalog
run_test "Database.properties loading and dynamic JDBC URL parsing" test_studio_properties_loading_and_jdbc_template
run_test "SpinDB Web Studio HTTP server & REST API smoke test" test_studio_server_smoke_startup_and_api

test_suite_end
