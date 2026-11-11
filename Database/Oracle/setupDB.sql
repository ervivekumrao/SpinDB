-- SPDX-License-Identifier: Apache-2.0
-- Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

DECLARE
    u_count INTEGER;
    t_count INTEGER;
BEGIN
    SELECT count(*) INTO u_count FROM all_users WHERE username = UPPER('userid');
    IF u_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER userid IDENTIFIED BY "0raclePa55w0rd" QUOTA UNLIMITED ON DATA';
        EXECUTE IMMEDIATE 'GRANT CREATE SESSION, CREATE TABLE, CONNECT, RESOURCE TO userid';
    END IF;

    SELECT count(*) INTO t_count FROM all_tables WHERE owner = UPPER('userid') AND table_name = 'TEST';
    IF t_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE TABLE userid.test (source int, cost int, part_number int)';
        EXECUTE IMMEDIATE 'GRANT INSERT, SELECT, UPDATE, DELETE ON userid.test TO userid';
    END IF;
END;
/

BEGIN
    ORDS.ENABLE_SCHEMA(
        p_enabled => TRUE,
        p_schema => 'userid',
        p_url_mapping_type => 'BASE_PATH',
        p_url_mapping_pattern => 'userid',
        p_auto_rest_auth=> TRUE
    );
    commit;
END;

ALTER USER userid QUOTA UNLIMITED ON DATA;
