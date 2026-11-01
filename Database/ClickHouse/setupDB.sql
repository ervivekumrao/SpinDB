-- SPDX-License-Identifier: Apache-2.0
-- Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

CREATE DATABASE IF NOT EXISTS userdata;
CREATE TABLE IF NOT EXISTS userdata.test (
    source Int32,
    cost Int32,
    part_number Int32,
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (source, part_number);
