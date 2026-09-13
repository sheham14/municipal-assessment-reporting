-- =============================================
-- Municipal Assessment & Tax Reporting
-- 01_create_reporting_procedures.sql
--
-- Parameterized stored procedures used as report datasets. RDL files
-- call these directly (EXEC rpt_X @Param = value) -- no SQL embedded in
-- the report itself, and every one of these can be tested standalone in
-- SSMS before it's ever wired into a report.
--
-- SET NOCOUNT ON at the top of every procedure: without it, SQL Server
-- sends a "N rows affected" message alongside the actual result set,
-- which can confuse a report engine (or any client) expecting exactly
-- one clean result set back.
--
-- Run after database/views/01_create_views.sql.
-- =============================================

USE MunicipalAssessment;
GO

DROP PROCEDURE IF EXISTS rpt_PropertyClassList;
GO

-- Lookup for the @PropertyClassID parameter's dropdown in Report 1. A
-- static 5-row list, but going through a procedure rather than letting
-- the report embed a raw SELECT keeps every bit of report logic --
-- including parameter value lists -- in one place that's testable in
-- SSMS, consistent with "no SQL embedded in RDL files."
CREATE PROCEDURE rpt_PropertyClassList
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PropertyClassID, ClassName FROM PropertyClass ORDER BY ClassName;
END
GO

DROP PROCEDURE IF EXISTS rpt_AssessmentTotalsByWardClass;
GO

-- Report 1: assessment totals by ward and property class.
-- @PropertyClassID is optional -- NULL means "all classes".
CREATE PROCEDURE rpt_AssessmentTotalsByWardClass
    @TaxYear         SMALLINT,
    @PropertyClassID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        w.WardID,
        w.WardName,
        pc.PropertyClassID,
        pc.ClassName,
        PropertyCount        = COUNT(*),
        TotalAssessedValue   = SUM(a.AssessedValue),
        AverageAssessedValue = AVG(a.AssessedValue)
    FROM Assessment a
    JOIN Property p      ON p.PropertyID = a.PropertyID
    JOIN Ward w           ON w.WardID = p.WardID
    JOIN PropertyClass pc ON pc.PropertyClassID = p.PropertyClassID
    WHERE a.TaxYear = @TaxYear
      AND (@PropertyClassID IS NULL OR p.PropertyClassID = @PropertyClassID)
    GROUP BY w.WardID, w.WardName, pc.PropertyClassID, pc.ClassName
    ORDER BY w.WardID, pc.ClassName;
END
GO

DROP PROCEDURE IF EXISTS rpt_WardSummary;
GO

-- Report 2 (top level): one row per ward, drill-through source.
-- Assessment and TaxBill are both 1-row-per-property-per-year by
-- design (UNIQUE constraints), so joining both to Property for the
-- same @TaxYear can't fan out or double-count.
CREATE PROCEDURE rpt_WardSummary
    @TaxYear SMALLINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        w.WardID,
        w.WardName,
        PropertyCount      = COUNT(DISTINCT p.PropertyID),
        TotalAssessedValue = SUM(a.AssessedValue),
        TotalBillAmount    = SUM(tb.BillAmount)
    FROM Ward w
    JOIN Property p ON p.WardID = w.WardID
    LEFT JOIN Assessment a ON a.PropertyID = p.PropertyID AND a.TaxYear = @TaxYear
    LEFT JOIN TaxBill tb   ON tb.PropertyID = p.PropertyID AND tb.TaxYear = @TaxYear
    GROUP BY w.WardID, w.WardName
    ORDER BY w.WardID;
END
GO

DROP PROCEDURE IF EXISTS rpt_PropertyDetailByWard;
GO

-- Report 2 (drill-through target): every property in one ward, with its
-- current owner(s), assessed value, and bill/payment status for the
-- year. Built on both reporting views.
CREATE PROCEDURE rpt_PropertyDetailByWard
    @WardID  INT,
    @TaxYear SMALLINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        cpo.PropertyID,
        cpo.ParcelNumber,
        cpo.AddressLine1,
        cpo.UnitNumber,
        cpo.ClassName,
        cpo.OwnerNames,
        a.AssessedValue,
        tbps.BillAmount,
        tbps.AmountPaid,
        tbps.BalanceOutstanding
    FROM vw_CurrentPropertyOwnership cpo
    LEFT JOIN Assessment a             ON a.PropertyID = cpo.PropertyID AND a.TaxYear = @TaxYear
    LEFT JOIN vw_TaxBillPaymentStatus tbps ON tbps.PropertyID = cpo.PropertyID AND tbps.TaxYear = @TaxYear
    WHERE cpo.WardID = @WardID
    ORDER BY cpo.AddressLine1;
END
GO

DROP PROCEDURE IF EXISTS rpt_ArrearsAging;
GO

-- Report 3: every bill with an outstanding balance, aged as of a given
-- date. DaysPastDue can be negative (bill not yet due) -- that's the
-- "Current" bucket, not an error. Aging buckets and the concept of
-- "arrears" here are simplifying assumptions documented in the README,
-- not a claim about real municipal billing practice.
CREATE PROCEDURE rpt_ArrearsAging
    @AsOfDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        tbps.TaxBillID,
        tbps.ParcelNumber,
        tbps.WardName,
        tbps.ClassName,
        tbps.TaxYear,
        tbps.BillAmount,
        tbps.AmountPaid,
        tbps.BalanceOutstanding,
        DaysPastDue = DATEDIFF(DAY, tbps.DueDate, @AsOfDate),
        AgingBucket =
            CASE
                WHEN DATEDIFF(DAY, tbps.DueDate, @AsOfDate) <= 0  THEN 'Current'
                WHEN DATEDIFF(DAY, tbps.DueDate, @AsOfDate) <= 30 THEN '1-30 Days'
                WHEN DATEDIFF(DAY, tbps.DueDate, @AsOfDate) <= 60 THEN '31-60 Days'
                WHEN DATEDIFF(DAY, tbps.DueDate, @AsOfDate) <= 90 THEN '61-90 Days'
                ELSE '90+ Days'
            END,
        -- Text buckets sort wrong alphabetically ("90+ Days" < "Current",
        -- since digits sort before letters) -- this gives the report a
        -- column to sort/group on that actually orders Current first,
        -- 90+ last.
        AgingSortOrder =
            CASE
                WHEN DATEDIFF(DAY, tbps.DueDate, @AsOfDate) <= 0  THEN 1
                WHEN DATEDIFF(DAY, tbps.DueDate, @AsOfDate) <= 30 THEN 2
                WHEN DATEDIFF(DAY, tbps.DueDate, @AsOfDate) <= 60 THEN 3
                WHEN DATEDIFF(DAY, tbps.DueDate, @AsOfDate) <= 90 THEN 4
                ELSE 5
            END
    FROM vw_TaxBillPaymentStatus tbps
    WHERE tbps.BalanceOutstanding > 0
    ORDER BY AgingSortOrder, DaysPastDue DESC;
END
GO
