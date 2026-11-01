# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION
FROM mysql:${DB_VERSION}
LABEL maintainer="Vivek Umrao and SpinDB contributors"

EXPOSE 3306

#Change _VALUE at build time
#IN MYSQL schema and DB is same
ENV MYSQL_PORT 3306
ENV MYSQL_DATABASE MYSQL_DATABASE_VALUE
ENV MYSQL_USER MYSQL_USER_VALUE
ENV MYSQL_PASSWORD MYSQL_PASSWORD_VALUE
ENV MYSQL_ROOT_PASSWORD MYSQL_ROOT_PASSWORD_VALUE

COPY --chmod=0644 setupDB.sql /docker-entrypoint-initdb.d

#Update sql file with environment variable values so no need to update multiple places
RUN sed -i "s/userdata/${MYSQL_DATABASE}/g" /docker-entrypoint-initdb.d/setupDB.sql
RUN sed -i "s/userid/${MYSQL_USER}/g" /docker-entrypoint-initdb.d/setupDB.sql
RUN sed -i "s/userPassword/${MYSQL_PASSWORD}/g" /docker-entrypoint-initdb.d/setupDB.sql

HEALTHCHECK --interval=60s --timeout=15s --start-period=20s --retries=10 CMD mysqladmin ping -h localhost -u ${MYSQL_USER} --password=${MYSQL_PASSWORD}