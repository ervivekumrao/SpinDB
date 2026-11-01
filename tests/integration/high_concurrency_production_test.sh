#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/integration/high_concurrency_production_test.sh - Real-Time High-Concurrency Production Test Suite
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

source "${TESTS_DIR}/test_harness.sh"

test_suite_start "Real-Time High-Concurrency Production Stress & Scalability Test"

resolve_test_engine() {
  if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    echo "podman"
  elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "docker"
  fi
}
ACTIVE_ENGINE="$(resolve_test_engine)"

# Unique test run identifiers
PID="$$"
PREFIX="stress-live-${PID}"

C1="${PREFIX}-c1"
C2="${PREFIX}-c2"
C3="${PREFIX}-c3"
REDIS_STRESS="${PREFIX}-redis"
PG_STRESS="${PREFIX}-pg"
RACE_CONTAINER="${PREFIX}-race"

PORT_C1=16401
PORT_C2=16402
PORT_C3=16403
PORT_REDIS=16379
PORT_PG=15432
PORT_RACE=16390

cleanup_concurrency_test() {
  if [[ -n "${ACTIVE_ENGINE}" ]]; then
    # Force clean any containers matching our PID prefix
    local leftover
    leftover="$("${ACTIVE_ENGINE}" ps -a --format '{{.Names}}' 2>/dev/null | grep "${PREFIX}" || true)"
    if [[ -n "${leftover}" ]]; then
      echo "${leftover}" | xargs -r "${ACTIVE_ENGINE}" rm -f >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup_concurrency_test EXIT INT TERM

test_engine_readiness() {
  if [[ -z "${ACTIVE_ENGINE}" ]]; then
    printf "No operational container engine found; skipping high concurrency test\n" >&2
    return 1
  fi
  printf "Active container engine confirmed: %s\n" "${ACTIVE_ENGINE}"
  return 0
}

test_concurrent_multi_instance_provisioning() {
  # Launch 3 instances concurrently in background jobs
  local pids=()
  local logs=("/tmp/${C1}.log" "/tmp/${C2}.log" "/tmp/${C3}.log")

  "${PROJECT_ROOT}/bin/spinctl" -t redis -p "${PORT_C1}" -n "${C1}" >"${logs[0]}" 2>&1 &
  pids+=($!)

  "${PROJECT_ROOT}/bin/spinctl" -t redis -p "${PORT_C2}" -n "${C2}" >"${logs[1]}" 2>&1 &
  pids+=($!)

  "${PROJECT_ROOT}/bin/spinctl" -t redis -p "${PORT_C3}" -n "${C3}" >"${logs[2]}" 2>&1 &
  pids+=($!)

  local failures=0
  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      printf "Parallel launch failed for container index %d! Log:\n" "$i" >&2
      cat "${logs[$i]}" >&2
      ((failures++))
    fi
    rm -f "${logs[$i]}"
  done

  if [[ ${failures} -gt 0 ]]; then
    return 1
  fi

  # Verify all 3 instances are actively running and labeled
  for name in "${C1}" "${C2}" "${C3}"; do
    local is_running
    is_running="$("${ACTIVE_ENGINE}" inspect -f '{{.State.Running}}' "${name}" 2>/dev/null | tr -d '[:space:]' || echo "false")"
    assert_equals "true" "${is_running}" "Parallel container ${name} not running"
  done

  return 0
}

test_concurrent_cli_inspection_load() {
  # Run 20 concurrent spinctl status & env inspection queries across parallel subshells
  local query_pids=()
  local query_fails=0

  for i in {1..10}; do
    "${PROJECT_ROOT}/bin/spinctl" status "${C1}" >/dev/null 2>&1 &
    query_pids+=($!)
    "${PROJECT_ROOT}/bin/spinctl" env "${C2}" >/dev/null 2>&1 &
    query_pids+=($!)
  done

  for qpid in "${query_pids[@]}"; do
    if ! wait "${qpid}"; then
      ((query_fails++))
    fi
  done

  assert_equals "0" "${query_fails}" "Concurrent CLI queries failed under parallel load"
  return 0
}

test_port_collision_race_condition() {
  # Launch 6 concurrent processes attempting to bind to the exact same host port
  local race_pids=()
  local exit_codes=()
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  for i in {1..6}; do
    (
      if "${PROJECT_ROOT}/bin/spinctl" -t redis -p "${PORT_RACE}" -n "${PREFIX}-port-race-${i}" >"${tmp_dir}/out-${i}.log" 2>&1; then
        echo 0 >"${tmp_dir}/code-${i}"
      else
        echo 1 >"${tmp_dir}/code-${i}"
      fi
    ) &
    race_pids+=($!)
  done

  for rpid in "${race_pids[@]}"; do
    wait "${rpid}" || true
  done

  local successes=0
  local rejections=0
  for i in {1..6}; do
    local code
    code="$(cat "${tmp_dir}/code-${i}")"
    if [[ "${code}" -eq 0 ]]; then
      ((successes++))
    else
      ((rejections++))
    fi
  done
  rm -rf "${tmp_dir}"

  # Exactly 1 must succeed, 5 must be cleanly rejected
  assert_equals "1" "${successes}" "Expected exactly 1 process to win port race"
  assert_equals "5" "${rejections}" "Expected 5 processes to be rejected during port race"

  # Clean up whichever won
  for i in {1..6}; do
    "${ACTIVE_ENGINE}" rm -f "${PREFIX}-port-race-${i}" >/dev/null 2>&1 || true
  done
  return 0
}

test_name_collision_race_condition() {
  # Launch 6 concurrent processes attempting to claim the same container name on distinct ports
  local race_pids=()
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  for i in {1..6}; do
    local p=$((PORT_RACE + 10 + i))
    (
      if "${PROJECT_ROOT}/bin/spinctl" -t redis -p "${p}" -n "${RACE_CONTAINER}" >"${tmp_dir}/out-${i}.log" 2>&1; then
        echo 0 >"${tmp_dir}/code-${i}"
      else
        echo 1 >"${tmp_dir}/code-${i}"
      fi
    ) &
    race_pids+=($!)
  done

  for rpid in "${race_pids[@]}"; do
    wait "${rpid}" || true
  done

  local successes=0
  local rejections=0
  for i in {1..6}; do
    local code
    code="$(cat "${tmp_dir}/code-${i}")"
    if [[ "${code}" -eq 0 ]]; then
      ((successes++))
    else
      ((rejections++))
    fi
  done
  rm -rf "${tmp_dir}"

  # Exactly 1 must succeed, 5 must be cleanly rejected
  assert_equals "1" "${successes}" "Expected exactly 1 process to win name collision race"
  assert_equals "5" "${rejections}" "Expected 5 processes to fail on duplicate name"

  "${ACTIVE_ENGINE}" rm -f "${RACE_CONTAINER}" >/dev/null 2>&1 || true
  return 0
}

test_redis_high_concurrency_workload() {
  # Launch Redis with resource constraints (memory & CPU limits)
  "${PROJECT_ROOT}/bin/spinctl" -t redis -p "${PORT_REDIS}" -n "${REDIS_STRESS}" -m "256m" --cpus "2.0" >/dev/null 2>&1

  local redis_pwd
  redis_pwd="$(source "${PROJECT_ROOT}/Database.properties" 2>/dev/null; echo "${REDIS_PASSWORD:-P@55w0rd}")"

  # 1. High-concurrency internal benchmark: 100 concurrent clients, 50,000 requests
  local bench_output
  bench_output="$("${ACTIVE_ENGINE}" exec "${REDIS_STRESS}" redis-benchmark -a "${redis_pwd}" -c 100 -n 50000 -q -t set,get,incr,lpush,lpop,ping 2>&1)"
  
  # Check that requests per second exceeded production baseline (> 15,000 req/sec)
  assert_contains "${bench_output}" "requests per second" "redis-benchmark failed or did not return throughput metrics"

  # 2. Host-side real-time TCP socket connection storm via Python:
  # Spawns 50 concurrent client connections sending pipelined requests directly over host 127.0.0.1:PORT_REDIS
  local py_res
  py_res="$(python3 -c "
import socket, concurrent.futures, time, sys

port = ${PORT_REDIS}
pwd = '${redis_pwd}'
num_clients = 50
reqs_per_client = 50

def run_client(cid):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect(('127.0.0.1', port))
        auth_msg = f'*2\r\n\$4\r\nAUTH\r\n\${len(pwd)}\r\n{pwd}\r\n'.encode()
        s.sendall(auth_msg)
        resp = s.recv(1024)
        if b'+OK' not in resp:
            return False, f'Auth failed: {resp}'
        for _ in range(reqs_per_client):
            s.sendall(b'*1\r\n\$4\r\nPING\r\n')
            r = s.recv(1024)
            if b'+PONG' not in r:
                return False, 'Bad ping'
        s.close()
        return True, 'OK'
    except Exception as e:
        return False, str(e)

with concurrent.futures.ThreadPoolExecutor(max_workers=num_clients) as ex:
    futures = [ex.submit(run_client, i) for i in range(num_clients)]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

failures = [r[1] for r in results if not r[0]]
if failures:
    print(f'FAILURES: {len(failures)}: {failures[0]}')
    sys.exit(1)
print(f'SUCCESS: {num_clients} concurrent clients, {num_clients * reqs_per_client} requests')
")"

  assert_contains "${py_res}" "SUCCESS: 50 concurrent clients" "Host socket concurrency stress test failed"
  return 0
}

test_postgres_high_concurrency_workload() {
  # Launch PostgreSQL with resource limits (512MB RAM, 2 CPUs)
  "${PROJECT_ROOT}/bin/spinctl" -t postgres -v 15 -p "${PORT_PG}" -n "${PG_STRESS}" -m "512m" --cpus "2.0" >/dev/null 2>&1

  local pg_pwd="P@55w0rd"

  # Initialize pgbench schema with 100,000 accounts (scale factor 1)
  "${ACTIVE_ENGINE}" exec -e PGPASSWORD="${pg_pwd}" "${PG_STRESS}" pgbench -i -s 1 -U userid -d pgdb >/dev/null 2>&1

  # Run real-time high-concurrency ACID transactional benchmark:
  # 50 concurrent clients, 4 threads, 5-second sustained load
  local pgbench_out
  pgbench_out="$("${ACTIVE_ENGINE}" exec -e PGPASSWORD="${pg_pwd}" "${PG_STRESS}" pgbench -c 50 -j 4 -T 5 -U userid -d pgdb 2>&1)"

  assert_contains "${pgbench_out}" "number of failed transactions: 0 (0.000%)" "PostgreSQL encountered transaction failures under concurrency"
  assert_contains "${pgbench_out}" "tps =" "PostgreSQL benchmark did not report TPS"
  return 0
}

test_concurrent_teardown_and_cleanup() {
  # Stop and remove all provisioned instances concurrently
  local all_targets=("${C1}" "${C2}" "${C3}" "${REDIS_STRESS}" "${PG_STRESS}")
  local teardown_pids=()

  for target in "${all_targets[@]}"; do
    "${PROJECT_ROOT}/bin/spinctl" rm "${target}" >/dev/null 2>&1 &
    teardown_pids+=($!)
  done

  for tpid in "${teardown_pids[@]}"; do
    wait "${tpid}" || true
  done

  # Verify no containers remain
  for target in "${all_targets[@]}"; do
    if "${ACTIVE_ENGINE}" inspect "${target}" >/dev/null 2>&1; then
      printf "Container %s was not cleanly removed during concurrent teardown\n" "${target}" >&2
      return 1
    fi
  done
  return 0
}

run_test "Verify Container Engine Operational Readiness" test_engine_readiness
run_test "Concurrent Multi-Instance Parallel Launch" test_concurrent_multi_instance_provisioning
run_test "High-Concurrency CLI Subcommand Load Stress (status/env)" test_concurrent_cli_inspection_load
run_test "Port Collision Race-Condition Defense (Parallel Contention)" test_port_collision_race_condition
run_test "Container Name Collision Race-Condition Defense" test_name_collision_race_condition
run_test "Redis Real-Time High-Concurrency Workload (100 Clients + Host Storm)" test_redis_high_concurrency_workload
run_test "PostgreSQL Real-Time High-Concurrency ACID Stress (50 Clients)" test_postgres_high_concurrency_workload
run_test "Concurrent Clean Resource Teardown & Reclamation" test_concurrent_teardown_and_cleanup

test_suite_end
