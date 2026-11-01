# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

ARG DB_VERSION=7-alpine
FROM redis:${DB_VERSION}
LABEL maintainer="Vivek Umrao and SpinDB contributors"

EXPOSE 6379

ENV REDIS_PASSWORD=REDIS_PASSWORD_VALUE

COPY --chmod=0755 entrypoint.sh /usr/local/bin/redis-custom-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/redis-custom-entrypoint.sh"]

HEALTHCHECK --interval=20s --timeout=5s --start-period=5s --retries=5 CMD redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null | grep -q PONG || redis-cli ping 2>/dev/null | grep -q PONG || exit 1
