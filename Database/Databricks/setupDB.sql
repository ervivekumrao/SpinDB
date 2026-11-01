-- SPDX-License-Identifier: Apache-2.0
-- Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

CREATE DATABASE IF NOT EXISTS userdata;
USE userdata;
CREATE TABLE IF NOT EXISTS userdata.test (
    source INT,
    cost INT,
    part_number INT
) USING DELTA;
