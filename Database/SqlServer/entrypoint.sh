#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

set -e

# Resolve sqlcmd binary location
if [[ -f /opt/mssql-tools/bin/sqlcmd ]]; then
  SQLCMD_BIN="/opt/mssql-tools/bin/sqlcmd"
elif [[ -f /opt/mssql-tools18/bin/sqlcmd ]]; then
  SQLCMD_BIN="/opt/mssql-tools18/bin/sqlcmd -C"
else
  SQLCMD_BIN="sqlcmd -C"
fi

# Asynchronously wait for SQL Server and apply initialization scripts
(
  for i in $(seq 1 45); do
    if ${SQLCMD_BIN} -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -Q "SELECT 1" >/dev/null 2>&1; then
      echo "SQL Server engine is responsive. Executing setupDB.sql..."
      ${SQLCMD_BIN} -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -i /var/custom/setupDB.sql || true
      echo "SQL Server initialization script applied successfully."
      break
    fi
    sleep 2
  done
) &

exec /opt/mssql/bin/sqlservr
