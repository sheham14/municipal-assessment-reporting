-- =============================================
-- Municipal Assessment & Tax Reporting
-- 04_enable_query_store.sql
--
-- Enables Query Store: SQL Server's built-in mechanism for automatically
-- tracking every query's execution plans and runtime performance over
-- time, without anyone having to manually capture STATISTICS IO/TIME or
-- an execution plan by hand. Complements (doesn't replace) the manual
-- before/after analysis done in performance/tuning-notes.md.
--
-- QUERY_CAPTURE_MODE = AUTO: only tracks queries significant enough to
-- matter (by execution count/resource use), not every ad-hoc query ever
-- run against the database -- avoiding unbounded storage growth.
--
-- Run any time after the schema exists.
-- =============================================

USE master;
GO

ALTER DATABASE MunicipalAssessment SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    MAX_STORAGE_SIZE_MB = 100,
    INTERVAL_LENGTH_MINUTES = 60,
    QUERY_CAPTURE_MODE = AUTO,
    SIZE_BASED_CLEANUP_MODE = AUTO
);
GO
