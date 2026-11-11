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
      if [ -f /var/custom/setupDB.sql ]; then
        [ -n "${MSSQL_DB}" ] && [ "${MSSQL_DB}" != "MSSQL_DB_VALUE" ] && sed -i -e "s/mssqldb/${MSSQL_DB}/g" /var/custom/setupDB.sql
        [ -n "${MSSQL_USER}" ] && [ "${MSSQL_USER}" != "MSSQL_USER_VALUE" ] && sed -i -e "s/userid/${MSSQL_USER}/g" /var/custom/setupDB.sql
        [ -n "${MSSQL_PASSWORD}" ] && [ "${MSSQL_PASSWORD}" != "MSSQL_PASSWORD_VALUE" ] && sed -i -e "s/P@55w0rd/${MSSQL_PASSWORD}/g" -e "s/userpass/${MSSQL_PASSWORD}/g" /var/custom/setupDB.sql
        [ -n "${MSSQL_SCHEMA}" ] && [ "${MSSQL_SCHEMA}" != "MSSQL_SCHEMA_VALUE" ] && sed -i -e "s/userdata/${MSSQL_SCHEMA}/g" /var/custom/setupDB.sql
      fi
      ${SQLCMD_BIN} -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -i /var/custom/setupDB.sql || true
      echo "SQL Server initialization script applied successfully."
      break
    fi
    sleep 2
  done
) &

exec /opt/mssql/bin/sqlservr
