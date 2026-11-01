# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION
FROM postgres:${DB_VERSION}
LABEL maintainer="Vivek Umrao and SpinDB contributors"

EXPOSE 5432

ENV LANG en_US.utf8
ENV POSTGRES_DB POSTGRES_DB_VALUE
ENV POSTGRES_USER POSTGRES_USER_VALUE
ENV POSTGRES_PASSWORD POSTGRES_PASSWORD_VALUE
ENV POSTGRES_SCHEMA POSTGRES_SCHEMA_VALUE
ENV POSTGRES_HOST_AUTH_METHOD scram-sha-256
ENV DEBIAN_FRONTEND noninteractive
ENV PGXS /usr/lib/postgresql/16/lib/pgxs/src/makefiles/pgxs.mk
COPY --chmod=0644 setupDB.sql /docker-entrypoint-initdb.d/

#Update sql file with environment variable values so no need to update multiple places
RUN sed -i -e "s/userid/${POSTGRES_USER}/g" /docker-entrypoint-initdb.d/setupDB.sql
RUN sed -i -e "s/userdata/${POSTGRES_SCHEMA}/g" /docker-entrypoint-initdb.d/setupDB.sql

HEALTHCHECK --interval=60s --timeout=15s --start-period=20s --retries=10 CMD pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}