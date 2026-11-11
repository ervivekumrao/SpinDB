# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION
FROM ghcr.io/oracle/adb-free:$DB_VERSION
#FROM ghcr.io/oracle/adb-free:latest
#FROM ghcr.io/oracle/adb-free:latest-23ai
LABEL maintainer="Vivek Umrao and SpinDB contributors"
EXPOSE 1521

#ENV WORKLOAD_TYPE ADW
ENV WORKLOAD_TYPE ATP
ENV WALLET_PASSWORD WALLET_PASSWORD_VALUE
ENV ADMIN_PASSWORD ADMIN_PASSWORD_VALUE
ENV DATABASE_NAME DATABASE_NAME_VALUE
ENV USER_NAME USER_NAME_VALUE
ENV USER_PASSWORD USER_PASSWORD_VALUE

COPY --chmod=0644 setupDB.sql /u01/scripts/setupDB.sql

#Update sql file with environment variable values so no need to update multiple places
RUN sed -i -e "s/userid/${USER_NAME}/g" /u01/scripts/setupDB.sql
RUN sed -i -e "s/0raclePa55w0rd/${USER_PASSWORD}/g" -e "s/password/${USER_PASSWORD}/g" /u01/scripts/setupDB.sql

#Add setupDB.sql run command to default /u01/scripts/entrypoint.sh file
RUN sed -i -e 's/# Tail on alert log and wait (otherwise container will exit)/#Execute setupDB.sql file \necho \"@\/u01\/scripts\/setupDB.sql\" | sqlplus admin\/\"${ADMIN_PASSWORD}\"@localhost:1521\/\"${DATABASE_NAME}\" \n\n# Tail on alert log and wait (otherwise container will exit)/g' /u01/scripts/entrypoint.sh