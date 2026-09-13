-- =============================================
-- Municipal Assessment & Tax Reporting
-- 03_tuning_indexes.sql
--
-- One deliberate index, added for a measured reason (see
-- performance/tuning-notes.md for the full before/after analysis) --
-- not "indexed everything."
--
-- vw_TaxBillPaymentStatus (used by rpt_ArrearsAging and
-- rpt_PropertyDetailByWard) computes, per bill, SUM(PaymentAmount) FROM
-- Payment WHERE TaxBillID = <this bill>. Payment had no index on
-- TaxBillID -- only its own PK on PaymentID -- so this correlated
-- lookup could not seek, only scan, once per bill. Measured on
-- rpt_ArrearsAging (237,816 bills, no parameter narrows the row count):
-- 3.8 seconds elapsed, 1,202,754 logical reads, a Worktable scanned
-- 237,816 times.
--
-- TaxBillID + INCLUDE(PaymentAmount) makes this a covering index for
-- exactly that aggregation: SQL Server can seek straight to a bill's
-- payments and sum them from the index alone, never touching the base
-- Payment table.
--
-- Run after database/schema/02_create_tables.sql (or any time
-- afterward -- this is additive and doesn't require rebuilding data).
-- =============================================

USE MunicipalAssessment;
GO

DROP INDEX IF EXISTS IX_Payment_TaxBillID ON Payment;
GO

CREATE NONCLUSTERED INDEX IX_Payment_TaxBillID
    ON Payment (TaxBillID)
    INCLUDE (PaymentAmount);
GO
