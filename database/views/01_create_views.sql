-- =============================================
-- Municipal Assessment & Tax Reporting
-- 01_create_views.sql
--
-- Reporting views: the reusable joins that the stored procedures (report
-- datasets) build on. Reports never query these directly -- per the
-- spec, RDL datasets call stored procedures only.
--
-- Run after the transform scripts (database/transform/*.sql).
-- =============================================

USE MunicipalAssessment;
GO

DROP VIEW IF EXISTS vw_CurrentPropertyOwnership;
GO

-- One row per property, with its ward/class resolved and its CURRENT
-- owner(s) resolved -- "current" means the PropertyOwner row with
-- EffectiveEndDate IS NULL, not "the most recently inserted row". This
-- is the effective-dating design decision actually being used. A
-- property can have more than one current co-owner, so STRING_AGG
-- combines them into one display string; a property can also have zero
-- current owners (the 1,550 rows with a rejected ownership record --
-- see docs/decisions-log.md), which is why the owner joins are LEFT
-- JOINs, not inner joins.
CREATE VIEW vw_CurrentPropertyOwnership AS
SELECT
    p.PropertyID,
    p.ParcelNumber,
    p.AddressLine1,
    p.UnitNumber,
    p.City,
    p.PostalCode,
    w.WardID,
    w.WardName,
    pc.PropertyClassID,
    pc.ClassName,
    OwnerNames = STRING_AGG(o.OwnerName, '; ')
FROM Property p
JOIN Ward w ON w.WardID = p.WardID
JOIN PropertyClass pc ON pc.PropertyClassID = p.PropertyClassID
LEFT JOIN PropertyOwner po ON po.PropertyID = p.PropertyID AND po.EffectiveEndDate IS NULL
LEFT JOIN [Owner] o ON o.OwnerID = po.OwnerID
GROUP BY p.PropertyID, p.ParcelNumber, p.AddressLine1, p.UnitNumber, p.City, p.PostalCode,
         w.WardID, w.WardName, pc.PropertyClassID, pc.ClassName;
GO

DROP VIEW IF EXISTS vw_TaxBillPaymentStatus;
GO

-- One row per bill, with total payments applied and the outstanding
-- balance computed. This is the base the arrears/aging report runs on.
-- OUTER APPLY (not a plain LEFT JOIN + GROUP BY) because it only needs
-- to aggregate Payment, not any of the other joined columns -- cheaper
-- and avoids a second GROUP BY across every selected column.
CREATE VIEW vw_TaxBillPaymentStatus AS
SELECT
    tb.TaxBillID,
    tb.PropertyID,
    p.ParcelNumber,
    p.WardID,
    w.WardName,
    p.PropertyClassID,
    pc.ClassName,
    tb.TaxYear,
    tb.AssessedValueUsed,
    tb.TaxRateUsed,
    tb.BillAmount,
    tb.BillDate,
    tb.DueDate,
    AmountPaid = ISNULL(pay.TotalPaid, 0),
    BalanceOutstanding = tb.BillAmount - ISNULL(pay.TotalPaid, 0)
FROM TaxBill tb
JOIN Property p ON p.PropertyID = tb.PropertyID
JOIN Ward w ON w.WardID = p.WardID
JOIN PropertyClass pc ON pc.PropertyClassID = p.PropertyClassID
OUTER APPLY (
    SELECT TotalPaid = SUM(pm.PaymentAmount) FROM Payment pm WHERE pm.TaxBillID = tb.TaxBillID
) pay;
GO
