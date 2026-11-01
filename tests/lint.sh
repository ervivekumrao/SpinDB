#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
# ==============================================================================
# tests/lint.sh - Static Syntax & License Header Verification
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Running syntax validation on all shell scripts..."
failed=0

while IFS= read -r script; do
  if ! bash -n "${script}"; then
    echo "[FAIL] Syntax error in ${script}"
    failed=1
  fi
done < <(find "${PROJECT_ROOT}" -name "*.sh" -not -path "*/build*")

if command -v shellcheck >/dev/null 2>&1; then
  echo "==> Running Shellcheck..."
  shellcheck -e SC1091 "${PROJECT_ROOT}"/bin/spinctl "${PROJECT_ROOT}"/lib/*.sh || failed=1
else
  echo "[INFO] shellcheck not installed, skipping advanced linting."
fi

echo "==> Verifying SPDX-License-Identifier in source files..."
while IFS= read -r file; do
  if ! grep -q "SPDX-License-Identifier" "${file}"; then
    echo "[FAIL] Missing SPDX license in ${file}"
    failed=1
  fi
done < <(find "${PROJECT_ROOT}" \( -name "*.sh" -o -name "*.sql" -o -name "Dockerfile" \) -not -path "*/.git/*" -not -path "*/build*")

if [[ "${failed}" -eq 0 ]]; then
  echo "==> [PASS] All static and license checks passed!"
  exit 0
else
  echo "==> [FAIL] Some linting checks failed!"
  exit 1
fi
