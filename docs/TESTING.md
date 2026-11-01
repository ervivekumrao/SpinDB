# In-Depth Testing Guide: SpinDB

**SPDX-License-Identifier:** Apache-2.0  
**Copyright:** (c) 2024-2026 Vivek Umrao and SpinDB contributors.

---

## 1. Testing Framework Overview

SpinDB includes a comprehensive, multi-layer automated test suite that runs in under 5 seconds with zero external dependencies (requiring only Bash $\ge$ 4.0).

```
tests/
├── test_harness.sh           # Lightweight assertion library (assert_equals, assert_contains, etc.)
├── lint.sh                   # Static bash syntax validator and SPDX license auditor
├── smoke_test.sh             # End-to-end regression test suite
├── run_all_tests.sh          # Master test orchestrator running all suites
├── unit/                     # Unit test suites
│   ├── test_cli.sh           # CLI routing, flag order independence, error exit codes, pgvector
│   ├── test_config.sh        # Property resolution, password escaping, local override precedence
│   ├── test_dockerfiles.sh   # Valid FROM directives, port validation, 0777 permission check
│   ├── test_engine.sh        # OS detection, package manager command generation, fallback
│   ├── test_lifecycle.sh     # Container lifecycle subcommands (status, start, restart, etc.)
│   └── test_security.sh      # CLR policies, idempotent DDL, localhost binding, resource limits
└── integration/
    └── enterprise_live_test.sh # Real-time live container launch, health, and lifecycle verification
```

---

## 2. Running Tests

### 2.1 Running the Full Master Suite
To execute all static, unit, regression, and live production integration tests:

```bash
make test
# or directly:
./tests/run_all_tests.sh
```

### 2.2 Running Individual Test Suites
```bash
# Run static linting & license verification:
make lint

# Run unit tests:
./tests/unit/test_cli.sh
./tests/unit/test_config.sh
./tests/unit/test_dockerfiles.sh
./tests/unit/test_engine.sh
./tests/unit/test_lifecycle.sh
./tests/unit/test_security.sh

# Run live enterprise container test:
./tests/integration/enterprise_live_test.sh
```

---

## 3. Test Assertion Library (`tests/test_harness.sh`)

The testing harness executes each test in a lightweight isolated subshell, preventing test side-effects from leaking across test cases:

```bash
source tests/test_harness.sh

test_suite_start "My Custom Test Suite"

my_test_function() {
  local actual="hello"
  assert_equals "hello" "${actual}" "Values did not match"
  assert_contains "hello world" "world" "Substring not found"
}

run_test "My test case description" my_test_function

test_suite_end
```

### Available Assertions:
| Assertion | Signature | Description |
| :--- | :--- | :--- |
| `assert_equals` | `assert_equals <expected> <actual> [msg]` | Fails if `$expected != $actual` |
| `assert_contains` | `assert_contains <haystack> <needle> [msg]` | Fails if `$needle` is not in `$haystack` |
| `assert_file_exists`| `assert_file_exists <file_path>` | Fails if file does not exist |
| `assert_dir_exists` | `assert_dir_exists <dir_path>` | Fails if directory does not exist |

---

## 4. Writing New Tests

When adding a new database engine or modifying orchestrator libraries:
1. **Adding Engine Verification**: Update `tests/unit/test_dockerfiles.sh` and add the new engine key to `required_dbs` in `tests/smoke_test.sh`.
2. **Adding Config Keys**: Add unit test cases in `tests/unit/test_config.sh` verifying that complex passwords and connection strings resolve accurately.
3. **Running Quality Checks**: Run `make lint && make test` before committing.

---

## 5. CI/CD Integration Example (GitHub Actions)

A sample workflow configuration for continuous integration:

```yaml
name: Test Suite

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Podman
        run: sudo apt-get update && sudo apt-get install -y podman
      - name: Run Quality Gate & Test Suite
        run: make test
```
