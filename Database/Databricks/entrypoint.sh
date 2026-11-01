#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.
set -e

mkdir -p /opt/spark/data/warehouse 2>/dev/null || true

# Run Spark SQL Thrift Server with Delta Lake extensions
exec /opt/spark/bin/spark-submit \
  --class org.apache.spark.sql.hive.thriftserver.HiveThriftServer2 \
  --name "DatabricksLocal-ThriftServer" \
  --packages "io.delta:delta-spark_2.12:${DELTA_VERSION:-3.2.0}" \
  --conf "spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension" \
  --conf "spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog" \
  --conf "spark.sql.warehouse.dir=/opt/spark/data/warehouse" \
  --conf "spark.ui.port=4040" \
  --hiveconf hive.server2.thrift.port=10000 \
  --hiveconf hive.server2.thrift.bind.host=0.0.0.0 \
  "$@"
