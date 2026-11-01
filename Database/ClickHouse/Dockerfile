# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION=latest
FROM clickhouse/clickhouse-server:${DB_VERSION}
LABEL maintainer="Vivek Umrao and SpinDB contributors"

EXPOSE 8123 9000

ENV CLICKHOUSE_DB=CLICKHOUSE_DB_VALUE
ENV CLICKHOUSE_USER=CLICKHOUSE_USER_VALUE
ENV CLICKHOUSE_PASSWORD=CLICKHOUSE_PASSWORD_VALUE
ENV CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1

COPY --chmod=0644 setupDB.sql /docker-entrypoint-initdb.d/

RUN sed -i "s/userdata/${CLICKHOUSE_DB}/g" /docker-entrypoint-initdb.d/setupDB.sql

HEALTHCHECK --interval=20s --timeout=5s --start-period=10s --retries=5 CMD wget -q --spider 'http://localhost:8123/ping' || exit 1
