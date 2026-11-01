-- SPDX-License-Identifier: Apache-2.0
-- Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

CREATE TABLE IF NOT EXISTS userdata.test (source int, cost int, part_number int);
GRANT ALL PRIVILEGES ON *.* TO 'userid'@'%';
FLUSH PRIVILEGES;
CREATE USER IF NOT EXISTS 'userid'@'localhost' IDENTIFIED BY 'userPassword';
GRANT ALL PRIVILEGES ON *.* TO 'userid'@'localhost';
FLUSH PRIVILEGES;