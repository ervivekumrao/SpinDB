# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION=latest
FROM cockroachdb/cockroach:${DB_VERSION}
LABEL maintainer="Vivek Umrao and SpinDB contributors"

EXPOSE 26257 8080

ENV COCKROACH_DATABASE=COCKROACH_DATABASE_VALUE
ENV COCKROACH_USER=COCKROACH_USER_VALUE
ENV COCKROACH_PASSWORD=COCKROACH_PASSWORD_VALUE

COPY --chmod=0755 entrypoint.sh /docker-entrypoint.sh
COPY --chmod=0644 setupDB.sql /setupDB.sql

ENTRYPOINT ["/docker-entrypoint.sh"]

HEALTHCHECK --interval=20s --timeout=5s --start-period=10s --retries=5 CMD /cockroach/cockroach node status --insecure || exit 1
