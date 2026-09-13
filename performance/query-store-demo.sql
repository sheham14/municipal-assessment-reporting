-- =============================================
-- Municipal Assessment & Tax Reporting
-- query-store-demo.sql
--
-- Demonstrates Query Store actually working, using the same tuning
-- scenario as performance/tuning-notes.md: temporarily removes the
-- IX_Payment_TaxBillID index to reproduce the slow plan, runs
-- rpt_ArrearsAging, restores the index, runs it again. The underlying
-- query text inside vw_TaxBillPaymentStatus never changes -- only the
-- index does -- so Query Store should record this as ONE query_id with
-- TWO different plan_ids and two very different runtime_stats rows,
-- which is exactly the point: Query Store tracks plan changes over time
-- automatically, without anyone manually re-capturing STATISTICS
-- IO/TIME before and after like in the original tuning exercise.
--
-- Run after database/schema/04_enable_query_store.sql and
-- database/schema/03_tuning_indexes.sql (the index this script
-- temporarily drops and re-creates).
-- =============================================

USE MunicipalAssessment;
GO

-- Clean slate so this demo's two plans are easy to find, not mixed in
-- with unrelated history.
ALTER DATABASE MunicipalAssessment SET QUERY_STORE CLEAR;
GO

-- ---------- "Before": reproduce the slow plan ----------
-- Captured into a throwaway temp table rather than returned as a result
-- set -- rpt_ArrearsAging returns 71,000+ rows, and running this
-- through sqlcmd/SSMS otherwise dumps all of it twice for no reason;
-- only triggering the execution (so Query Store records it) matters
-- here, not seeing the output.
DROP INDEX IF EXISTS IX_Payment_TaxBillID ON Payment;
GO

CREATE TABLE #Discard (TaxBillID INT, ParcelNumber VARCHAR(20), WardName VARCHAR(50), ClassName VARCHAR(50), TaxYear SMALLINT, BillAmount DECIMAL(12,2), AmountPaid DECIMAL(12,2), BalanceOutstanding DECIMAL(12,2), DaysPastDue INT, AgingBucket VARCHAR(20), AgingSortOrder INT);
INSERT INTO #Discard EXEC rpt_ArrearsAging @AsOfDate = '2026-09-11';
DROP TABLE #Discard;
GO

-- ---------- "After": restore the tuning index ----------
CREATE NONCLUSTERED INDEX IX_Payment_TaxBillID
    ON Payment (TaxBillID)
    INCLUDE (PaymentAmount);
GO

CREATE TABLE #Discard (TaxBillID INT, ParcelNumber VARCHAR(20), WardName VARCHAR(50), ClassName VARCHAR(50), TaxYear SMALLINT, BillAmount DECIMAL(12,2), AmountPaid DECIMAL(12,2), BalanceOutstanding DECIMAL(12,2), DaysPastDue INT, AgingBucket VARCHAR(20), AgingSortOrder INT);
INSERT INTO #Discard EXEC rpt_ArrearsAging @AsOfDate = '2026-09-11';
DROP TABLE #Discard;
GO

-- ---------- What Query Store captured ----------
-- Same query_id both rows (identical SQL text -- only the index
-- changed), two different plan_ids, two very different cost profiles.

SELECT
    qsq.query_id,
    qsp.plan_id,
    CONVERT(VARCHAR(19), qsrs.last_execution_time) AS LastExecuted,
    qsrs.avg_duration / 1000.0                      AS AvgDurationMs,
    qsrs.avg_logical_io_reads                       AS AvgLogicalReads,
    qsrs.count_executions
FROM sys.query_store_query qsq
JOIN sys.query_store_query_text qsqt ON qsqt.query_text_id = qsq.query_text_id
JOIN sys.query_store_plan qsp        ON qsp.query_id = qsq.query_id
JOIN sys.query_store_runtime_stats qsrs ON qsrs.plan_id = qsp.plan_id
WHERE qsqt.query_sql_text LIKE '%vw_TaxBillPaymentStatus%'
   OR qsqt.query_sql_text LIKE '%OUTER APPLY%Payment%'
ORDER BY qsrs.last_execution_time;
GO
