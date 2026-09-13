-- =============================================
-- Municipal Assessment & Tax Reporting
-- 04_generate_assessment_data.sql
--
-- Generates StagingAssessment: one row per property per tax year
-- (2022-2026, matching TaxLevy) = 250,000 rows, plus ~250 deliberately
-- orphaned rows referencing a ParcelNumber that does not exist in
-- StagingPropertyOwnership at all.
--
-- Assessed values scale by property class (a base range per class) with
-- a per-PROPERTY annual growth rate applied across its 5 years, so the
-- same property's assessment rises smoothly year over year instead of
-- being independent random noise per row.
--
-- Deliberate defects on the linked rows:
--   - AssessedValue: 0 (~1%), negative (~1%), non-numeric text (~1%)
--   - AssessmentDate: malformed (~2%)
--
-- Follows the two-phase discipline from 03_generate_property_data.sql
-- (see docs/decisions-log.md for why): Phase 1 computes BaseValue/
-- GrowthPct once per property directly off the real
-- StagingPropertyOwnership table -- no join keyed on the computed random
-- values, so no risk of the runaway parallel plan hit earlier. Phase 2
-- CROSS JOINs that now fully-materialized table to a small static list
-- of tax years -- also not a join on a random value, since CROSS JOIN
-- has no join key at all.
--
-- Run after database/staging/03_generate_property_data.sql.
-- =============================================

USE MunicipalAssessment;
GO

TRUNCATE TABLE StagingAssessment;
GO

-- ---------- Phase 1: base value + growth rate, once per property ----------

IF OBJECT_ID('tempdb..#PropertyFinancials') IS NOT NULL DROP TABLE #PropertyFinancials;
CREATE TABLE #PropertyFinancials (
    ParcelNumber VARCHAR(20) PRIMARY KEY,
    BaseValue    DECIMAL(12,2),
    GrowthPct    DECIMAL(5,2)
);

INSERT INTO #PropertyFinancials (ParcelNumber, BaseValue, GrowthPct)
SELECT
    p.ParcelNumber,
    BaseValue =
        CASE p.PropertyClassName
            WHEN 'Residential'   THEN 200000 + (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 250000)
            WHEN 'Commercial'    THEN 500000 + (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 1000000)
            WHEN 'Industrial'    THEN 700000 + (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 1300000)
            WHEN 'Vacant Land'   THEN 50000  + (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 100000)
            WHEN 'Institutional' THEN 300000 + (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 500000)
        END,
    GrowthPct = 1.5 + (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 301) / 100.0
FROM StagingPropertyOwnership p;
GO

-- ---------- Phase 2: one row per property per tax year ----------

INSERT INTO StagingAssessment (ParcelNumber, TaxYear, AssessedValue, AssessmentDate)
SELECT
    pf.ParcelNumber,
    ty.TaxYear,

    AssessedValue =
        CASE
            WHEN r.ValueDefectRoll < 1 THEN '0'
            WHEN r.ValueDefectRoll < 2 THEN CAST(-1 * clean.CleanValue AS VARCHAR(20))
            WHEN r.ValueDefectRoll < 3 THEN 'N/A'
            ELSE CAST(clean.CleanValue AS VARCHAR(20))
        END,

    AssessmentDate =
        CASE
            WHEN r.DateDefectRoll < 1 THEN 'not-a-date'
            WHEN r.DateDefectRoll < 2 THEN CAST(ty.TaxYear AS VARCHAR(4)) + '-02-30'
            ELSE clean.CleanDate
        END

FROM #PropertyFinancials pf
CROSS JOIN (VALUES (2022,0),(2023,1),(2024,2),(2025,3),(2026,4)) AS ty(TaxYear, YearIndex)
CROSS APPLY (
    SELECT
        ValueDefectRoll = ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 100,
        DateDefectRoll  = ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 100,
        DayOffset       = ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 89
) r
CROSS APPLY (
    SELECT
        CleanValue = ROUND(pf.BaseValue * POWER(1 + pf.GrowthPct / 100.0, ty.YearIndex), 2),
        CleanDate  = CONVERT(VARCHAR(10), DATEADD(DAY, r.DayOffset, DATEFROMPARTS(ty.TaxYear, 1, 1)), 120)
) clean;
GO

-- ---------- Orphan rows: ParcelNumber not present in staging property data ----------

INSERT INTO StagingAssessment (ParcelNumber, TaxYear, AssessedValue, AssessmentDate)
SELECT
    ParcelNumber = 'PAR-9' + RIGHT('00000' + CAST(g.value AS VARCHAR(5)), 5),
    TaxYear = 2022 + (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 5),
    AssessedValue = CAST(200000 + (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 300000) AS VARCHAR(20)),
    AssessmentDate = CONVERT(VARCHAR(10), DATEADD(DAY, ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 1800, '2022-01-01'), 120)
FROM GENERATE_SERIES(1, 250) g;
GO

DROP TABLE IF EXISTS #PropertyFinancials;
GO

SELECT COUNT(*) AS NumRows FROM StagingAssessment;
GO
