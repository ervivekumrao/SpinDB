# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION=lts
FROM mariadb:${DB_VERSION}
LABEL maintainer="Vivek Umrao and SpinDB contributors"

EXPOSE 3306

ENV MARIADB_DATABASE=MARIADB_DATABASE_VALUE
ENV MARIADB_USER=MARIADB_USER_VALUE
ENV MARIADB_PASSWORD=MARIADB_PASSWORD_VALUE
ENV MARIADB_ROOT_PASSWORD=MARIADB_ROOT_PASSWORD_VALUE

COPY --chmod=0644 setupDB.sql /docker-entrypoint-initdb.d/

RUN sed -i "s/userdata/${MARIADB_DATABASE}/g" /docker-entrypoint-initdb.d/setupDB.sql && \
    sed -i "s/userid/${MARIADB_USER}/g" /docker-entrypoint-initdb.d/setupDB.sql

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=5 CMD mariadb-admin ping -u root -p"${MARIADB_ROOT_PASSWORD}" || healthcheck.sh --connect || exit 1
