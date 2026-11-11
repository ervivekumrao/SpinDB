-- SPDX-License-Identifier: Apache-2.0
-- Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

CREATE DATABASE IF NOT EXISTS userdata;
CREATE USER IF NOT EXISTS userid WITH PASSWORD 'P@55w0rd';
GRANT ALL ON DATABASE userdata TO userid;
CREATE TABLE IF NOT EXISTS userdata.test (
    source INT,
    cost INT,
    part_number INT
);
GRANT ALL ON TABLE userdata.test TO userid;
