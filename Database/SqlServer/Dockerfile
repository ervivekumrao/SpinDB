# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION
FROM mcr.microsoft.com/mssql/server:${DB_VERSION}
#FROM mcr.microsoft.com/mssql/server:${DB_VERSION}-latest
LABEL maintainer="Vivek Umrao and SpinDB contributors"
EXPOSE 1433

ENV ACCEPT_EULA Y
# SQL Server admin account name is sa
ENV MSSQL_SA_PASSWORD MSSQL_SA_PASSWORD_VALUE
ENV MSSQL_DB MSSQL_DB_VALUE
ENV MSSQL_USER MSSQL_USER_VALUE
ENV MSSQL_PASSWORD MSSQL_PASSWORD_VALUE
ENV MSSQL_SCHEMA MSSQL_SCHEMA_VALUE
ENV MSSQL_PID Developer
ENV MSSQL_TCP_PORT 1433

WORKDIR /var/custom
COPY --chmod=0755 entrypoint.sh /var/custom/entrypoint.sh
COPY --chmod=0644 setupDB.sql /var/custom/setupDB.sql

#Update sql file with environment variable values so no need to update multiple places
RUN sed -i -e "s/mssqldb/${MSSQL_DB}/g" /var/custom/setupDB.sql
RUN sed -i -e "s/userid/${MSSQL_USER}/g" /var/custom/setupDB.sql
RUN sed -i -e "s/P@55w0rd/${MSSQL_PASSWORD}/g" -e "s/userpass/${MSSQL_PASSWORD}/g" /var/custom/setupDB.sql
RUN sed -i -e "s/userdata/${MSSQL_SCHEMA}/g" /var/custom/setupDB.sql

ENTRYPOINT ["bash", "-x", "/var/custom/entrypoint.sh"]

HEALTHCHECK --interval=60s --timeout=15s --start-period=60s --retries=10 CMD if (ls /opt/mssql-tools/bin/sqlcmd >/dev/null 2>&1); then export SQLCMD_PATH=/opt/mssql-tools/bin/sqlcmd; else export SQLCMD_PATH=/opt/mssql-tools18/bin/sqlcmd; fi && (${SQLCMD_PATH} -S localhost -U sa -P ${MSSQL_SA_PASSWORD} -C -Q "SELECT 1" || exit 1)