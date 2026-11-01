#!/usr/bin/env sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

set -e

if [ -n "${REDIS_PASSWORD}" ] && [ "${REDIS_PASSWORD}" != "REDIS_PASSWORD_VALUE" ]; then
    exec redis-server --requirepass "${REDIS_PASSWORD}" "$@"
else
    exec redis-server "$@"
fi
