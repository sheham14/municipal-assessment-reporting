-- =============================================
-- Municipal Assessment & Tax Reporting
-- 05_transform_payments.sql
--
-- Transforms StagingPayment into Payment, resolved to a TaxBill via
-- Property + TaxYear.
--
-- Rejected and logged if the ParcelNumber/TaxYear doesn't resolve to a
-- real TaxBill -- this catches three kinds of orphan at once, without
-- needing to special-case any of them: the explicit fake-year payments
-- (TaxYear 2027, which has no levy/assessment/bill at all), any payment
-- whose target property/year had an Assessment that got rejected
-- upstream (no assessment survived -> no bill was ever generated for it
-- -> any payment aimed at it is now an orphan too), and any payment
-- against a parcel number that was itself an orphan back in
-- StagingAssessment. Also rejected: non-numeric or non-positive
-- PaymentAmount, and an invalid PaymentDate.
--
-- Run after database/transform/04_generate_tax_bills.sql.
-- =============================================

USE MunicipalAssessment;
GO

DELETE FROM Payment;
DELETE FROM RejectedRow WHERE SourceTable = 'StagingPayment';
GO

INSERT INTO Payment (TaxBillID, PaymentDate, PaymentAmount, PaymentMethod)
SELECT
    tb.TaxBillID,
    TRY_CAST(sp.PaymentDate AS DATE),
    TRY_CAST(sp.PaymentAmount AS DECIMAL(12,2)),
    sp.PaymentMethod
FROM StagingPayment sp
JOIN Property p ON p.ParcelNumber = sp.ParcelNumber
JOIN TaxBill tb ON tb.PropertyID = p.PropertyID AND tb.TaxYear = sp.TaxYear
WHERE TRY_CAST(sp.PaymentAmount AS DECIMAL(12,2)) > 0
  AND LTRIM(RTRIM(sp.PaymentDate)) <> ''
  AND TRY_CAST(sp.PaymentDate AS DATE) IS NOT NULL;
GO

INSERT INTO RejectedRow (SourceTable, SourceKey, RejectionReason, RawData)
SELECT
    'StagingPayment',
    ISNULL(sp.ParcelNumber, '(null)') + '/' + CAST(sp.TaxYear AS VARCHAR(4)),
    CASE
        WHEN p.PropertyID IS NULL THEN 'Orphan: ParcelNumber not found in Property'
        WHEN tb.TaxBillID IS NULL THEN 'Orphan: no matching TaxBill for this property/year'
        WHEN TRY_CAST(sp.PaymentAmount AS DECIMAL(12,2)) IS NULL THEN 'PaymentAmount not numeric'
        WHEN TRY_CAST(sp.PaymentAmount AS DECIMAL(12,2)) <= 0 THEN 'PaymentAmount not positive'
        WHEN LTRIM(RTRIM(sp.PaymentDate)) = '' OR TRY_CAST(sp.PaymentDate AS DATE) IS NULL THEN 'Invalid PaymentDate'
    END,
    CONCAT('Amount=', sp.PaymentAmount, '; Date=', sp.PaymentDate)
FROM StagingPayment sp
LEFT JOIN Property p ON p.ParcelNumber = sp.ParcelNumber
LEFT JOIN TaxBill tb ON tb.PropertyID = p.PropertyID AND tb.TaxYear = sp.TaxYear
WHERE p.PropertyID IS NULL
   OR tb.TaxBillID IS NULL
   OR TRY_CAST(sp.PaymentAmount AS DECIMAL(12,2)) IS NULL
   OR TRY_CAST(sp.PaymentAmount AS DECIMAL(12,2)) <= 0
   OR LTRIM(RTRIM(sp.PaymentDate)) = ''
   OR TRY_CAST(sp.PaymentDate AS DATE) IS NULL;
GO

SELECT 'Payment' AS TableName, COUNT(*) AS NumRows FROM Payment
UNION ALL SELECT 'RejectedRow (this stage)', COUNT(*) FROM RejectedRow WHERE SourceTable = 'StagingPayment';
GO
