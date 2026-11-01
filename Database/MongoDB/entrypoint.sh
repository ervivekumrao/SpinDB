#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.


echo "db.$MONGO_INITDB_SCHEMA.insertOne({test : { source: 1, cost: 1, part_number:1 } })"  | mongosh "mongodb://$MONGO_INITDB_ROOT_USERNAME:$MONGO_INITDB_ROOT_PASSWORD@localhost:27017/$MONGO_INITDB_DATABASE?authSource=admin"