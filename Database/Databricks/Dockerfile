# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION=3.5.3
FROM apache/spark:${DB_VERSION}
LABEL maintainer="Vivek Umrao and SpinDB contributors"

USER root

EXPOSE 10000 4040

ENV SPARK_PUBLIC_DNS=localhost
ENV DELTA_VERSION=3.2.0

WORKDIR /opt/spark

COPY --chmod=0755 entrypoint.sh /opt/spark/entrypoint.sh
COPY --chmod=0644 setupDB.sql /opt/spark/setupDB.sql

USER spark

ENTRYPOINT ["/opt/spark/entrypoint.sh"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=5 CMD (bash -c '</dev/tcp/localhost/10000') || exit 1
