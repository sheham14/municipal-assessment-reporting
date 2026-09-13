-- =============================================
-- Municipal Assessment & Tax Reporting
-- 03_transform_assessments.sql
--
-- Transforms StagingAssessment into Assessment. Clears Payment and
-- TaxBill first (both ultimately depend on Assessment existing) so a
-- second full rebuild doesn't hit a foreign key violation. Rerun 04/05
-- afterward to repopulate what this clears.
--
-- Rejected and logged if: ParcelNumber doesn't resolve to a real
-- Property (orphans -- includes the ~250 deliberately fake parcels),
-- AssessedValue isn't numeric or isn't > 0 (catches the 0/negative/
-- non-numeric defects in one check via TRY_CAST), or AssessmentDate
-- isn't a valid date.
--
-- Uses TRY_CAST throughout rather than CAST guarded by a separate
-- ISNUMERIC/ISDATE check in the WHERE clause -- after the runaway-plan
-- and ABS(CHECKSUM(NEWID())) overflow issues hit while building the
-- staging generators (docs/decisions-log.md), TRY_CAST (returns NULL on
-- failure instead of erroring) is the safer default rather than trusting
-- SQL Server to evaluate WHERE conditions strictly left-to-right before
-- the SELECT list.
--
-- Run after database/transform/02_transform_properties_owners.sql.
-- =============================================

USE MunicipalAssessment;
GO

DELETE FROM Payment;
DELETE FROM TaxBill;
DELETE FROM Assessment;
DELETE FROM RejectedRow WHERE SourceTable = 'StagingAssessment';
GO

-- TRY_CAST('' AS DATE) does NOT return NULL -- SQL Server treats an
-- empty string as the "zero date" and returns 1900-01-01 instead of
-- failing. Blank/whitespace-only values are excluded explicitly rather
-- than trusted to TRY_CAST alone (found the hard way in
-- 02_transform_properties_owners.sql -- see docs/decisions-log.md).

INSERT INTO Assessment (PropertyID, TaxYear, AssessedValue, AssessmentDate)
SELECT
    p.PropertyID,
    a.TaxYear,
    TRY_CAST(a.AssessedValue AS DECIMAL(12,2)),
    TRY_CAST(a.AssessmentDate AS DATE)
FROM StagingAssessment a
JOIN Property p ON p.ParcelNumber = a.ParcelNumber
WHERE TRY_CAST(a.AssessedValue AS DECIMAL(12,2)) > 0
  AND LTRIM(RTRIM(a.AssessmentDate)) <> ''
  AND TRY_CAST(a.AssessmentDate AS DATE) IS NOT NULL;
GO

INSERT INTO RejectedRow (SourceTable, SourceKey, RejectionReason, RawData)
SELECT
    'StagingAssessment',
    ISNULL(a.ParcelNumber, '(null)') + '/' + CAST(a.TaxYear AS VARCHAR(4)),
    CASE
        WHEN p.PropertyID IS NULL THEN 'Orphan: ParcelNumber not found in Property'
        WHEN TRY_CAST(a.AssessedValue AS DECIMAL(12,2)) IS NULL THEN 'AssessedValue not numeric'
        WHEN TRY_CAST(a.AssessedValue AS DECIMAL(12,2)) <= 0 THEN 'AssessedValue not positive'
        WHEN LTRIM(RTRIM(a.AssessmentDate)) = '' OR TRY_CAST(a.AssessmentDate AS DATE) IS NULL THEN 'Invalid AssessmentDate'
    END,
    CONCAT('Value=', a.AssessedValue, '; Date=', a.AssessmentDate)
FROM StagingAssessment a
LEFT JOIN Property p ON p.ParcelNumber = a.ParcelNumber
WHERE p.PropertyID IS NULL
   OR TRY_CAST(a.AssessedValue AS DECIMAL(12,2)) IS NULL
   OR TRY_CAST(a.AssessedValue AS DECIMAL(12,2)) <= 0
   OR LTRIM(RTRIM(a.AssessmentDate)) = ''
   OR TRY_CAST(a.AssessmentDate AS DATE) IS NULL;
GO

SELECT 'Assessment' AS TableName, COUNT(*) AS NumRows FROM Assessment
UNION ALL SELECT 'RejectedRow (this stage)', COUNT(*) FROM RejectedRow WHERE SourceTable = 'StagingAssessment';
GO
