-- =============================================
-- Municipal Assessment & Tax Reporting
-- 04_generate_tax_bills.sql
--
-- Generates TaxBill -- not staged, not transformed from raw data, but
-- COMPUTED: one bill per validated Assessment row that has a matching
-- TaxLevy rate for the same property class and tax year.
--
-- AssessedValueUsed and TaxRateUsed are copied in right now and never
-- touched again by anything downstream -- this is the historical
-- snapshot design decision (spec section 3 / docs/decisions-log.md). If
-- Assessment or TaxLevy values are corrected later, every bill already
-- issued still shows exactly what it said when it was generated.
--
-- Assumption (documented, not a claim about real billing cycles):
--   BillDate = AssessmentDate + 110 days (assessment finalized
--     Jan-Mar, bill mailed mid-year -- a real, common municipal
--     pattern, not just a convenient number)
--   DueDate  = BillDate + 60 days
--
-- The offset matters for more than realism: AssessmentDate always falls
-- in Jan-Mar (see 04_generate_assessment_data.sql), so a short offset
-- like "+14 days" puts every DueDate in Mar-Jun regardless of tax year --
-- which means even the most recent tax year's bills are already months
-- overdue by the time anyone runs the arrears report later in the year,
-- and EVERY outstanding bill lands in the "90+ Days" bucket with no
-- variety at all. Confirmed this the hard way: after the first version
-- of this script (a +14/+74 day offset), rpt_ArrearsAging put all
-- 71,315 outstanding bills in a single bucket. Pushing the offset out so
-- DueDate lands mid-to-late in the tax year means the most recent year's
-- unpaid bills naturally straddle "today," giving genuine spread across
-- Current/1-30/31-60/61-90, while older tax years' unpaid bills
-- correctly land in 90+ (they should -- that debt really is old).
--
-- Clears Payment first (it references TaxBill) so a second full rebuild
-- doesn't hit a foreign key violation. Rerun 05 afterward to repopulate
-- Payment.
--
-- Run after database/transform/03_transform_assessments.sql.
-- =============================================

USE MunicipalAssessment;
GO

DELETE FROM Payment;
DELETE FROM TaxBill;
GO

INSERT INTO TaxBill (PropertyID, TaxYear, AssessedValueUsed, TaxRateUsed, BillAmount, BillDate, DueDate)
SELECT
    a.PropertyID,
    a.TaxYear,
    a.AssessedValue,
    tl.TaxRate,
    ROUND(a.AssessedValue * tl.TaxRate, 2),
    DATEADD(DAY, 110, a.AssessmentDate),
    DATEADD(DAY, 170, a.AssessmentDate)
FROM Assessment a
JOIN Property p ON p.PropertyID = a.PropertyID
JOIN TaxLevy tl ON tl.PropertyClassID = p.PropertyClassID AND tl.TaxYear = a.TaxYear;
GO

SELECT 'TaxBill' AS TableName, COUNT(*) AS NumRows FROM TaxBill;
GO
