-- =============================================
-- Municipal Assessment & Tax Reporting
-- 05_generate_payment_data.sql
--
-- Generates StagingPayment against the property/tax-year combinations
-- that look like they'll become real bills (a valid, positive, numeric
-- AssessedValue in StagingAssessment). Payment behavior per bill target:
--   ~70% pay in full (one payment row for the full expected amount)
--   ~15% pay partially (one payment row for 30-70% of the amount --
--     feeds the arrears/aging report)
--   ~15% pay nothing (no row at all)
-- Plus ~150 explicit orphan payments: real parcels, tax year 2027, which
-- has no assessment/levy/bill at all.
--
-- Two more natural sources of "orphan" payments fall out for free and
-- don't need separate generation: payments against a property/year whose
-- assessment was itself defective (0/negative/non-numeric value, or a
-- malformed date) will have no real bill to attach to once transform
-- rejects that assessment row.
--
-- Expected bill amount = AssessedValue x that class/year's TaxRate (from
-- the already-seeded TaxLevy), so payments are realistically sized
-- relative to an actual bill, not an arbitrary fraction of assessed
-- value. Follows the two-phase discipline used throughout this stage:
-- Phase 1 materializes #ExpectedBills from three already-concrete
-- tables (no NEWID()-keyed joins); Phase 2 draws payments off that
-- materialized table.
--
-- Run after database/staging/04_generate_assessment_data.sql.
-- =============================================

USE MunicipalAssessment;
GO

TRUNCATE TABLE StagingPayment;
GO

-- ---------- Phase 1: expected bill amount per clean assessment ----------

IF OBJECT_ID('tempdb..#ExpectedBills') IS NOT NULL DROP TABLE #ExpectedBills;
CREATE TABLE #ExpectedBills (
    ParcelNumber       VARCHAR(20),
    TaxYear             SMALLINT,
    ExpectedBillAmount DECIMAL(12,2),
    PRIMARY KEY (ParcelNumber, TaxYear)
);

INSERT INTO #ExpectedBills (ParcelNumber, TaxYear, ExpectedBillAmount)
SELECT
    a.ParcelNumber,
    a.TaxYear,
    ROUND(CAST(a.AssessedValue AS DECIMAL(12,2)) * tl.TaxRate, 2)
FROM StagingAssessment a
JOIN StagingPropertyOwnership p ON p.ParcelNumber = a.ParcelNumber
JOIN PropertyClass pc           ON pc.ClassName = p.PropertyClassName
JOIN TaxLevy tl                 ON tl.PropertyClassID = pc.PropertyClassID AND tl.TaxYear = a.TaxYear
WHERE ISNUMERIC(a.AssessedValue) = 1
  AND TRY_CAST(a.AssessedValue AS DECIMAL(12,2)) > 0;
GO

-- ---------- Phase 2: payments against expected bills ----------

INSERT INTO StagingPayment (ParcelNumber, TaxYear, PaymentDate, PaymentAmount, PaymentMethod)
SELECT
    eb.ParcelNumber,
    eb.TaxYear,

    PaymentDate = CONVERT(VARCHAR(10), DATEADD(DAY, r.DayOffset, DATEFROMPARTS(eb.TaxYear, 1, 1)), 120),

    PaymentAmount =
        CASE
            WHEN r.PayRoll < 70 THEN CAST(eb.ExpectedBillAmount AS VARCHAR(20))
            ELSE CAST(ROUND(eb.ExpectedBillAmount * r.PartialFraction, 2) AS VARCHAR(20))
        END,

    PaymentMethod =
        CASE r.MethodPick
            WHEN 0 THEN 'Cheque'
            WHEN 1 THEN 'Online'
            WHEN 2 THEN 'In-Person'
            ELSE 'Bank Draft'
        END

FROM #ExpectedBills eb
CROSS APPLY (
    SELECT
        PayRoll         = ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 100,
        DayOffset        = CAST(30 + (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 210) AS INT),
        PartialFraction = 0.30 + (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 41) / 100.0,
        MethodPick      = ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 4
) r
WHERE r.PayRoll < 85;  -- the remaining ~15% get no payment row at all (fully unpaid)
GO

-- ---------- Orphan payments: real parcels, tax year 2027 (no bill exists) ----------

INSERT INTO StagingPayment (ParcelNumber, TaxYear, PaymentDate, PaymentAmount, PaymentMethod)
SELECT TOP 150
    ParcelNumber,
    2027,
    '2027-03-15',
    CAST(300 + (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 2000) AS VARCHAR(20)),
    'Online'
FROM StagingPropertyOwnership
ORDER BY NEWID();
GO

DROP TABLE IF EXISTS #ExpectedBills;
GO

SELECT COUNT(*) AS NumRows FROM StagingPayment;
GO
