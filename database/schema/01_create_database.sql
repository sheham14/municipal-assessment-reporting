-- =============================================
-- Municipal Assessment & Tax Reporting
-- 01_create_database.sql
--
-- Creates the database. Safe to re-run: skips creation if it already exists.
-- =============================================

IF DB_ID('MunicipalAssessment') IS NULL
BEGIN
    CREATE DATABASE MunicipalAssessment;
END
GO
