-- =============================================
-- Municipal Assessment & Tax Reporting
-- 02_transform_properties_owners.sql
--
-- Transforms StagingPropertyOwnership into Property, Owner, and
-- PropertyOwner.
--
-- Property is the most "upstream" transformed table -- Assessment,
-- TaxBill, and Payment all ultimately depend on it existing. So this
-- script clears everything downstream too, in FK order, before
-- rebuilding -- otherwise a second full rebuild would hit a foreign key
-- violation trying to delete a Property that Assessment/TaxBill/Payment
-- rows still point to. If you rerun this script, rerun 03/04/05
-- afterward to repopulate what it just cleared.
--
-- Cleaning vs. rejecting: casing/whitespace defects in addresses and
-- owner names are FIXED (normalized to uppercase, whitespace collapsed,
-- trimmed), not rejected -- that's the "handle" half of the spec's
-- "handle or reject" instruction. This normalization is also how
-- near-duplicate owner names collapse into one Owner row: "John Smith",
-- "john  smith", and "John  Smith" all normalize to the same cleaned
-- string. See docs/decisions-log.md for the known limitation this
-- creates (two genuinely different owners who happen to share a name
-- would also be merged -- name alone can't distinguish that case, in
-- this system or any other).
--
-- An unparseable OwnershipStartDate doesn't block the Property row --
-- the parcel is still real -- it blocks just that ownership record,
-- rejected and logged. Net effect: a small number of properties end up
-- with no current owner in PropertyOwner, which is itself a realistic,
-- worth-flagging data quality state.
--
-- Run after database/transform/01_create_transform_objects.sql.
-- =============================================

USE MunicipalAssessment;
GO

DELETE FROM Payment;
DELETE FROM TaxBill;
DELETE FROM Assessment;
DELETE FROM PropertyOwner;
DELETE FROM Property;
DELETE FROM [Owner];
DELETE FROM RejectedRow WHERE SourceTable = 'StagingPropertyOwnership';
GO

-- ---------- Materialize cleaned values once, reused by every insert below ----------

IF OBJECT_ID('tempdb..#Cleaned') IS NOT NULL DROP TABLE #Cleaned;

SELECT
    sp.ParcelNumber,
    sp.WardName,
    sp.PropertyClassName,
    sp.City,
    sp.PostalCode,
    sp.OwnershipStartDate AS RawStartDate,
    UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(sp.AddressLine1, '  ', ' '), '  ', ' '), '  ', ' ')))) AS CleanAddress,
    NULLIF(LTRIM(RTRIM(sp.UnitNumber)), '') AS CleanUnitNumber,
    NULLIF(UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(sp.PrimaryOwnerName, '  ', ' '), '  ', ' '), '  ', ' ')))), '') AS CleanPrimaryOwner,
    NULLIF(UPPER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(sp.SecondaryOwnerName, '  ', ' '), '  ', ' '), '  ', ' ')))), '') AS CleanSecondaryOwner,
    -- TRY_CAST('' AS DATE) does NOT return NULL -- SQL Server treats an
    -- empty string as the "zero date" and silently returns 1900-01-01.
    -- Blank/whitespace-only values must be caught explicitly before
    -- TRY_CAST, or they'd sneak through as a fake real date instead of
    -- being rejected.
    CASE WHEN LTRIM(RTRIM(sp.OwnershipStartDate)) = '' THEN NULL
         ELSE TRY_CAST(sp.OwnershipStartDate AS DATE)
    END AS CleanStartDate
INTO #Cleaned
FROM StagingPropertyOwnership sp;
GO

-- ---------- Property ----------
-- Rejected if ParcelNumber/AddressLine1 is missing, or WardName/
-- PropertyClassName doesn't resolve to a real lookup row. None of these
-- actually trigger against our generated data (the generator never left
-- those fields blank or unresolvable) -- the checks exist because a
-- transform that only works on well-behaved input isn't really
-- validating anything.

INSERT INTO Property (ParcelNumber, AddressLine1, UnitNumber, City, PostalCode, WardID, PropertyClassID)
SELECT
    c.ParcelNumber, c.CleanAddress, c.CleanUnitNumber, c.City, c.PostalCode, w.WardID, pc.PropertyClassID
FROM #Cleaned c
JOIN Ward w ON w.WardName = c.WardName
JOIN PropertyClass pc ON pc.ClassName = c.PropertyClassName
WHERE c.ParcelNumber IS NOT NULL AND LTRIM(RTRIM(c.ParcelNumber)) <> ''
  AND c.CleanAddress IS NOT NULL AND c.CleanAddress <> '';
GO

INSERT INTO RejectedRow (SourceTable, SourceKey, RejectionReason, RawData)
SELECT
    'StagingPropertyOwnership',
    ISNULL(c.ParcelNumber, '(null)'),
    CASE
        WHEN c.ParcelNumber IS NULL OR LTRIM(RTRIM(c.ParcelNumber)) = '' THEN 'Missing ParcelNumber'
        WHEN c.CleanAddress IS NULL OR c.CleanAddress = '' THEN 'Missing AddressLine1'
        WHEN w.WardID IS NULL THEN 'Unresolvable WardName: ' + ISNULL(c.WardName, '(null)')
        WHEN pc.PropertyClassID IS NULL THEN 'Unresolvable PropertyClassName: ' + ISNULL(c.PropertyClassName, '(null)')
    END,
    CONCAT('Ward=', c.WardName, '; Class=', c.PropertyClassName)
FROM #Cleaned c
LEFT JOIN Ward w ON w.WardName = c.WardName
LEFT JOIN PropertyClass pc ON pc.ClassName = c.PropertyClassName
WHERE c.ParcelNumber IS NULL OR LTRIM(RTRIM(c.ParcelNumber)) = ''
   OR c.CleanAddress IS NULL OR c.CleanAddress = ''
   OR w.WardID IS NULL
   OR pc.PropertyClassID IS NULL;
GO

-- ---------- Owner ----------
-- Distinct cleaned names across both owner columns.

INSERT INTO [Owner] (OwnerName)
SELECT DISTINCT CleanedName
FROM (
    SELECT CleanPrimaryOwner AS CleanedName FROM #Cleaned WHERE CleanPrimaryOwner IS NOT NULL
    UNION
    SELECT CleanSecondaryOwner FROM #Cleaned WHERE CleanSecondaryOwner IS NOT NULL
) allNames;
GO

-- ---------- PropertyOwner (effective-dated) ----------

INSERT INTO PropertyOwner (PropertyID, OwnerID, EffectiveStartDate, EffectiveEndDate)
SELECT p.PropertyID, o.OwnerID, c.CleanStartDate, NULL
FROM #Cleaned c
JOIN Property p ON p.ParcelNumber = c.ParcelNumber
JOIN [Owner] o ON o.OwnerName = c.CleanPrimaryOwner
WHERE c.CleanPrimaryOwner IS NOT NULL AND c.CleanStartDate IS NOT NULL;
GO

INSERT INTO PropertyOwner (PropertyID, OwnerID, EffectiveStartDate, EffectiveEndDate)
SELECT p.PropertyID, o.OwnerID, c.CleanStartDate, NULL
FROM #Cleaned c
JOIN Property p ON p.ParcelNumber = c.ParcelNumber
JOIN [Owner] o ON o.OwnerName = c.CleanSecondaryOwner
WHERE c.CleanSecondaryOwner IS NOT NULL AND c.CleanStartDate IS NOT NULL;
GO

INSERT INTO RejectedRow (SourceTable, SourceKey, RejectionReason, RawData)
SELECT
    'StagingPropertyOwnership',
    c.ParcelNumber,
    'Invalid OwnershipStartDate',
    c.RawStartDate
FROM #Cleaned c
JOIN Property p ON p.ParcelNumber = c.ParcelNumber
WHERE c.CleanPrimaryOwner IS NOT NULL AND c.CleanStartDate IS NULL;
GO

DROP TABLE IF EXISTS #Cleaned;
GO

SELECT 'Property' AS TableName, COUNT(*) AS NumRows FROM Property
UNION ALL SELECT 'Owner', COUNT(*) FROM [Owner]
UNION ALL SELECT 'PropertyOwner', COUNT(*) FROM PropertyOwner
UNION ALL SELECT 'RejectedRow (this stage)', COUNT(*) FROM RejectedRow WHERE SourceTable = 'StagingPropertyOwnership';
GO
