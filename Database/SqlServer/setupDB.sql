-- SPDX-License-Identifier: Apache-2.0
-- Copyright (c) 2024-2026 Vivek Umrao and SpinDB contributors.

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'mssqldb')
BEGIN
    CREATE DATABASE mssqldb;
END
GO

USE mssqldb;
GO

IF NOT EXISTS (SELECT name FROM sys.server_principals WHERE name = 'userid')
BEGIN
    CREATE LOGIN userid WITH PASSWORD = 'P@55w0rd', DEFAULT_DATABASE = mssqldb;
END
GO

IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = 'userid')
BEGIN
    CREATE USER userid FOR LOGIN userid;
END
GO

IF NOT EXISTS (SELECT name FROM sys.schemas WHERE name = 'userdata')
BEGIN
    EXEC('CREATE SCHEMA userdata AUTHORIZATION userid');
END
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'userdata.test') AND type in (N'U'))
BEGIN
    CREATE TABLE userdata.test (
        source int,
        cost int,
        part_number int
    );
END
GO