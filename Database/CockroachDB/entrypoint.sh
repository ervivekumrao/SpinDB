#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
set -e

# Run background setup once the node is accepting SQL queries
(
  for i in $(seq 1 30); do
    if /cockroach/cockroach sql --insecure -e "SELECT 1;" >/dev/null 2>&1; then
      sed -i "s/userdata/${COCKROACH_DATABASE}/g" /setupDB.sql
      sed -i "s/userid/${COCKROACH_USER}/g" /setupDB.sql
      sed -i "s/userPassword/${COCKROACH_PASSWORD}/g" /setupDB.sql
      /cockroach/cockroach sql --insecure < /setupDB.sql || true
      echo "CockroachDB initial database setup completed."
      break
    fi
    sleep 2
  done
) &

exec /cockroach/cockroach start-single-node --insecure --http-addr=0.0.0.0:8080 --listen-addr=0.0.0.0:26257 "$@"
