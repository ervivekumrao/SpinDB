#!/usr/bin/env sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
set -e

exec /app/snowflake-emulator -port 8080 "$@"
