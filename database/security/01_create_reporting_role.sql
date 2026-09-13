-- =============================================
-- Municipal Assessment & Tax Reporting
-- 01_create_reporting_role.sql
--
-- Least-privilege database role for reporting: EXECUTE on the reporting
-- stored procedures, SELECT on the reporting views, nothing else. No
-- direct access to any of the 9 base tables, staging tables, or the
-- RejectedRow log.
--
-- Ownership chaining note: since the stored procedures and the views/
-- tables they reference are all owned by dbo, EXECUTE on a procedure
-- alone would technically be enough for the procedure to work (SQL
-- Server skips the underlying permission check when caller and object
-- share the same owner). The views are granted separately anyway, per
-- the spec, so a future ad-hoc/self-service report could query an
-- approved view directly without needing a brand new stored procedure
-- for every question -- while the base tables stay fully locked down
-- either way.
--
-- The login's password lives in a :setvar variable rather than inline
-- in a CREATE LOGIN statement -- this repo is public on GitHub, so
-- keeping the one credential isolated and easy to override
-- (sqlcmd -v ReportingLoginPassword="...") is worth doing even for a
-- practice password that guards synthetic data.
--
-- The value below is a PLACEHOLDER, not a real credential -- set your
-- own before running this, either by editing this line or passing
-- -v ReportingLoginPassword="..." on the sqlcmd command line. (An
-- earlier real password was committed here by mistake and has since
-- been rotated on the server; this file was rewritten to never hold a
-- working credential again.)
--
-- Run after database/procedures/01_create_reporting_procedures.sql.
-- =============================================

:setvar ReportingLoginPassword "ChangeMe_SetYourOwnPassword!2026"

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'ssrs_reporting_svc')
BEGIN
    CREATE LOGIN ssrs_reporting_svc WITH PASSWORD = '$(ReportingLoginPassword)', CHECK_POLICY = ON;
END
GO

USE MunicipalAssessment;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'ssrs_reporting_svc')
BEGIN
    CREATE USER ssrs_reporting_svc FOR LOGIN ssrs_reporting_svc;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'ReportingRole' AND type = 'R')
BEGIN
    CREATE ROLE ReportingRole;
END
GO

ALTER ROLE ReportingRole ADD MEMBER ssrs_reporting_svc;
GO

GRANT EXECUTE ON OBJECT::dbo.rpt_AssessmentTotalsByWardClass TO ReportingRole;
GRANT EXECUTE ON OBJECT::dbo.rpt_WardSummary                 TO ReportingRole;
GRANT EXECUTE ON OBJECT::dbo.rpt_PropertyDetailByWard        TO ReportingRole;
GRANT EXECUTE ON OBJECT::dbo.rpt_ArrearsAging                TO ReportingRole;
GRANT EXECUTE ON OBJECT::dbo.rpt_PropertyClassList           TO ReportingRole;
GO

GRANT SELECT ON OBJECT::dbo.vw_CurrentPropertyOwnership TO ReportingRole;
GRANT SELECT ON OBJECT::dbo.vw_TaxBillPaymentStatus     TO ReportingRole;
GO
