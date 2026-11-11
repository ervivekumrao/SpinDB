#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
set -e

# Run background setup once the node is accepting SQL queries
(
  for i in $(seq 1 30); do
    if /cockroach/cockroach sql --insecure -e "SELECT 1;" >/dev/null 2>&1; then
      [ -n "${COCKROACH_DATABASE}" ] && [ "${COCKROACH_DATABASE}" != "COCKROACH_DATABASE_VALUE" ] && sed -i "s/userdata/${COCKROACH_DATABASE}/g" /setupDB.sql
      [ -n "${COCKROACH_USER}" ] && [ "${COCKROACH_USER}" != "COCKROACH_USER_VALUE" ] && sed -i "s/userid/${COCKROACH_USER}/g" /setupDB.sql
      [ -n "${COCKROACH_PASSWORD}" ] && [ "${COCKROACH_PASSWORD}" != "COCKROACH_PASSWORD_VALUE" ] && sed -i -e "s/P@55w0rd/${COCKROACH_PASSWORD}/g" -e "s/userPassword/${COCKROACH_PASSWORD}/g" /setupDB.sql
      /cockroach/cockroach sql --insecure < /setupDB.sql || true
      echo "CockroachDB initial database setup completed."
      break
    fi
    sleep 2
  done
) &

exec /cockroach/cockroach start-single-node --insecure --http-addr=0.0.0.0:8080 --listen-addr=0.0.0.0:26257 "$@"
