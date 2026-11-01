# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION=latest
FROM ghcr.io/nnnkkk7/snowflake-emulator:${DB_VERSION}
LABEL maintainer="Vivek Umrao and SpinDB contributors"

EXPOSE 8080

ENV SNOWFLAKE_DATABASE=SNOWFLAKE_DATABASE_VALUE
ENV SNOWFLAKE_SCHEMA=SNOWFLAKE_SCHEMA_VALUE
ENV SNOWFLAKE_USER=SNOWFLAKE_USER_VALUE
ENV SNOWFLAKE_PASSWORD=SNOWFLAKE_PASSWORD_VALUE

COPY --chmod=0755 entrypoint.sh /docker-entrypoint.sh
COPY --chmod=0644 setupDB.sql /setupDB.sql

ENTRYPOINT ["/docker-entrypoint.sh"]

HEALTHCHECK --interval=20s --timeout=5s --start-period=5s --retries=5 CMD wget -q --spider 'http://localhost:8080/' || exit 1
