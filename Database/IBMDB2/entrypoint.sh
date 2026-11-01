#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

echo "Waiting for DB2 engine to become available..."
for i in $(seq 1 40); do
  if su - "${DB2INSTANCE}" -c "db2start" >/dev/null 2>&1 || su - "${DB2INSTANCE}" -c "db2 connect to ${DBNAME};" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

echo "Executing the setup script now."
su - "${DB2INSTANCE}" -c "db2 create database ${DBNAME} automatic storage yes alias ${DBNAME} using codeset utf-8 territory us collate using system PAGESIZE 32768;" || true
su - "${DB2INSTANCE}" -c "db2 connect to ${DBNAME}; db2 update database configuration for ${DBNAME} using LOGFILSIZ 2048;" || true

echo "Adding application user..."
useradd -m -s /bin/bash -d "/database/config/${DBNAME}" "${USERID}" 2>/dev/null || true
echo "${USERPASS}" | passwd "${USERID}" --stdin 2>/dev/null || true

su - "${DB2INSTANCE}" -c "db2 connect to ${DBNAME}; db2 create schema ${USERSCHEMA} AUTHORIZATION ${USERID} CREATE TABLE test \\(source int, cost int, part_number int\\); db2 GRANT CONNECT ON DATABASE TO USER ${USERID};" || true

echo "DB2 initialization completed successfully."
