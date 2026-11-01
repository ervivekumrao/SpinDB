# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION
FROM mongo:${DB_VERSION}
LABEL maintainer="Vivek Umrao and SpinDB contributors"
EXPOSE 27017

ENV MONGO_INITDB_DATABASE MONGO_INITDB_DATABASE_VALUE
ENV MONGO_INITDB_ROOT_USERNAME MONGO_INITDB_ROOT_USERNAME_VALUE
ENV MONGO_INITDB_ROOT_PASSWORD MONGO_INITDB_ROOT_PASSWORD_VALUE
ENV MONGO_INITDB_SCHEMA MONGO_INITDB_SCHEMA_VALUE

COPY --chmod=0755 entrypoint.sh /docker-entrypoint-initdb.d/

HEALTHCHECK --interval=20s --timeout=15s --start-period=20s --retries=10 CMD echo 'db.runCommand({serverStatus:1}).ok' | mongosh admin -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --quiet | grep 1
