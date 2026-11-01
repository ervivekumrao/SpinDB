# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION
#FROM ibmcom/db2:${DB_VERSION}
#FROM ibmcom/db2:11.5.8.0
FROM icr.io/db2_community/db2:${DB_VERSION}
LABEL maintainer="Vivek Umrao and SpinDB contributors"
EXPOSE 50000

ENV LICENSE=accept
ENV DB2INSTANCE=DB2_DB2INSTANCE_VALUE
ENV DB2INST1_PASSWORD=DB2_DB2INST1_PASSWORD_VALUE
ENV DBNAME=DB2_DBNAME_VALUE
ENV USERID=DB2_USERID_VALUE
ENV USERPASS=DB2_USERPASS_VALUE
ENV USERSCHEMA=DB2_USERSCHEMA_VALUE
ENV BLU=false
ENV ENABLE_ORACLE_COMPATIBILITY=false
ENV UPDATEAVAIL=NO
ENV TO_CREATE_SAMPLEDB=false
ENV REPODB=false
ENV IS_OSXFS=false
ENV PERSISTENT_HOME=true
ENV HADR_ENABLED=false
#ENV ETCD_ENDPOINT=
#ENV ETCD_USERNAME=
#ENV ETCD_PASSWORD=

WORKDIR /var/custom
COPY --chmod=0755 entrypoint.sh /var/custom/

ENTRYPOINT ["/bin/bash", "-c", "(/var/custom/entrypoint.sh &); exec /var/db2_setup/include/db2_run"]

HEALTHCHECK --interval=60s --timeout=15s --start-period=60s --retries=10 CMD su - ${DB2INSTANCE} -c "db2 connect to ${DBNAME};"