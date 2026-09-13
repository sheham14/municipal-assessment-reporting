-- =============================================
-- Municipal Assessment & Tax Reporting
-- 03_generate_property_data.sql
--
-- Generates ~50,000 synthetic property/ownership rows into
-- StagingPropertyOwnership, with deliberate defects layered in:
--   - address casing/whitespace mangling (~5% of rows)
--   - UnitNumber populated only ~18% of the time (realistic, not a defect
--     per se -- exercises the nullable-optional-field handling)
--   - SecondaryOwnerName populated only ~12% of the time (same idea)
--   - owner-name near-duplicates via casing/whitespace (~5% of rows), on
--     top of natural repeats from a deliberately small name pool
--   - OwnershipStartDate malformed on ~3% of rows
--
-- Technique: GENERATE_SERIES(1, 50000) is the row generator (SQL Server
-- 2022+). Generation happens in two phases rather than one:
--
--   Phase 1 materializes every random draw (which pool item, which
--   defect, which house number, ...) into a plain temp table, #Seed --
--   nothing but GENERATE_SERIES and scalar NEWID()-based expressions,
--   no joins.
--   Phase 2 joins #Seed to the small name/street pools and builds the
--   final columns.
--
-- This two-phase split exists because of a genuine SQL Server gotcha
-- found while building this script: combining GENERATE_SERIES, a
-- CROSS APPLY computing NEWID()-based values, AND immediately joining
-- that same derived table to several lookup tables *in one statement*
-- produced a catastrophic parallel execution plan (confirmed via
-- sys.dm_exec_requests: over 20 minutes of CPU time and climbing, stuck
-- on CXCONSUMER parallelism waits, for a job that should take seconds).
-- Materializing the random values first, then joining the now-ordinary
-- temp table in a separate, simple statement, avoids it entirely.
--
-- Also note: every random draw is ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)),
-- not the more common ABS(CHECKSUM(NEWID())). CHECKSUM(NEWID()) returns
-- an INT, and INT's minimum value (-2147483648) has no positive INT
-- equivalent -- ABS() on that specific value throws an overflow error.
-- Rare per call, but with hundreds of thousands of calls across a script
-- meant to be rerun often, it will eventually get hit. Casting to BIGINT
-- first gives ABS() somewhere to put the result.
--
-- Run after database/staging/01_create_staging_tables.sql and
-- 02_seed_reference_data.sql.
-- =============================================

USE MunicipalAssessment;
GO

TRUNCATE TABLE StagingPropertyOwnership;
GO

-- ---------- Small pools to draw from ----------

IF OBJECT_ID('tempdb..#StreetNames') IS NOT NULL DROP TABLE #StreetNames;
CREATE TABLE #StreetNames (StreetID INT IDENTITY(1,1), StreetName VARCHAR(30));
INSERT INTO #StreetNames (StreetName) VALUES
('Maple'),('Oak'),('Elm'),('Birch'),('Cedar'),('Willow'),('Spruce'),('Pine'),
('Alder'),('Ash'),('Beech'),('Chestnut'),('Hawthorn'),('Juniper'),('Laurel'),
('Linden'),('Magnolia'),('Poplar'),('Rowan'),('Sycamore'),('Harbour'),
('Seaview'),('Hillcrest'),('Meadow'),('Brookside'),('Sunset'),('Ridge'),
('Orchard'),('Fieldstone'),('Lakeview');

IF OBJECT_ID('tempdb..#StreetTypes') IS NOT NULL DROP TABLE #StreetTypes;
CREATE TABLE #StreetTypes (StreetTypeID INT IDENTITY(1,1), StreetType VARCHAR(10));
INSERT INTO #StreetTypes (StreetType) VALUES
('St'),('Ave'),('Rd'),('Dr'),('Cres'),('Ln'),('Ct'),('Way');

IF OBJECT_ID('tempdb..#FirstNames') IS NOT NULL DROP TABLE #FirstNames;
CREATE TABLE #FirstNames (FirstNameID INT IDENTITY(1,1), FirstName VARCHAR(30));
INSERT INTO #FirstNames (FirstName) VALUES
('James'),('John'),('Robert'),('Michael'),('William'),('David'),('Richard'),
('Joseph'),('Mary'),('Patricia'),('Jennifer'),('Linda'),('Elizabeth'),('Susan'),
('Jessica'),('Sarah'),('Karen'),('Nancy'),('Margaret'),('Lisa'),('Daniel'),
('Matthew'),('Anthony'),('Mark'),('Paul'),('Steven'),('Andrew'),('Joshua'),
('Kevin'),('Brian'),('Emily'),('Ashley'),('Amanda'),('Michelle'),('Kimberly'),
('Amy'),('Angela'),('Melissa'),('Rebecca'),('Laura');

IF OBJECT_ID('tempdb..#LastNames') IS NOT NULL DROP TABLE #LastNames;
CREATE TABLE #LastNames (LastNameID INT IDENTITY(1,1), LastName VARCHAR(30));
INSERT INTO #LastNames (LastName) VALUES
('Sullivan'),('Murphy'),('Power'),('Ryan'),('Walsh'),('Kelly'),('Hussey'),
('Penney'),('Pike'),('Hann'),('Snow'),('Collins'),('Bishop'),('King'),
('Parsons'),('Hillier'),('Piercey'),('Squires'),('Chafe'),('Warren'),
('Legge'),('Fitzgerald'),('Careen'),('Hynes'),('Dean'),('Mercer'),('Rowe'),
('House'),('Loder'),('Coombs'),('Barnes'),('Osmond'),('Pittman'),('Clarke'),
('White'),('Taylor'),('Anderson'),('Brown'),('Smith'),('Wilson'),('Martin'),
('Thompson'),('Campbell'),('Stewart'),('Morris'),('Rogers'),('Reid'),
('Young'),('Baker'),('Coady');
GO

-- ---------- Phase 1: materialize every random draw ----------

IF OBJECT_ID('tempdb..#Seed') IS NOT NULL DROP TABLE #Seed;
CREATE TABLE #Seed (
    RowNum            INT PRIMARY KEY,
    ClassRoll         INT,
    AddressDefectRoll INT,
    OwnerDefectRoll   INT,
    DateDefectRoll    INT,
    UnitRoll          INT,
    SecondaryRoll     INT,
    HouseNumber       INT,
    UnitNum           INT,
    WardPick          INT,
    DaysOffset        INT,
    StreetPick        INT,
    StreetTypePick    INT,
    FirstPick1        INT,
    LastPick1         INT,
    FirstPick2        INT,
    LastPick2         INT,
    PostalCode        VARCHAR(10)
);

INSERT INTO #Seed
SELECT
    g.value,
    ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 100,
    ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 100,
    ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 100,
    ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 100,
    ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 100,
    ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 100,
    (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 999) + 1,
    (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 300) + 1,
    (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 5) + 1,
    ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 9490,
    (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 30) + 1,
    (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 8) + 1,
    (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 40) + 1,
    (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 50) + 1,
    (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 40) + 1,
    (ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 50) + 1,
    'A' + CAST(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 10 AS CHAR(1))
        + CHAR(65 + ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 26) + ' '
        + CAST(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 10 AS CHAR(1))
        + CHAR(65 + ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 26)
        + CAST(ABS(CAST(CHECKSUM(NEWID()) AS BIGINT)) % 10 AS CHAR(1))
FROM GENERATE_SERIES(1, 50000) g;
GO

-- ---------- Phase 2: resolve pool text + build final rows ----------

INSERT INTO StagingPropertyOwnership (
    ParcelNumber, AddressLine1, UnitNumber, City, PostalCode,
    WardName, PropertyClassName, PrimaryOwnerName, SecondaryOwnerName,
    OwnershipStartDate
)
SELECT
    ParcelNumber = 'PAR-' + RIGHT('000000' + CAST(s.RowNum AS VARCHAR(6)), 6),

    AddressLine1 =
        CASE
            WHEN s.AddressDefectRoll < 3 THEN UPPER(addr.BaseAddress)
            WHEN s.AddressDefectRoll < 5 THEN '  ' + REPLACE(addr.BaseAddress, ' ', '  ')
            ELSE addr.BaseAddress
        END,

    UnitNumber =
        CASE WHEN s.UnitRoll < 18 THEN CAST(s.UnitNum AS VARCHAR(10)) ELSE NULL END,

    City = 'St. John''s',

    PostalCode = s.PostalCode,

    WardName = 'Ward ' + CAST(s.WardPick AS VARCHAR(1)),

    PropertyClassName =
        CASE
            WHEN s.ClassRoll < 70 THEN 'Residential'
            WHEN s.ClassRoll < 82 THEN 'Commercial'
            WHEN s.ClassRoll < 90 THEN 'Industrial'
            WHEN s.ClassRoll < 97 THEN 'Vacant Land'
            ELSE 'Institutional'
        END,

    PrimaryOwnerName =
        CASE
            WHEN s.OwnerDefectRoll < 3 THEN LOWER(owner1.BaseOwner)
            WHEN s.OwnerDefectRoll < 5 THEN REPLACE(owner1.BaseOwner, ' ', '  ')
            ELSE owner1.BaseOwner
        END,

    SecondaryOwnerName =
        CASE WHEN s.SecondaryRoll < 12 THEN owner2.BaseOwner2 ELSE NULL END,

    OwnershipStartDate =
        CASE
            WHEN s.DateDefectRoll < 1 THEN 'not-a-date'
            WHEN s.DateDefectRoll < 2 THEN '2024-13-45'
            WHEN s.DateDefectRoll < 3 THEN ''
            ELSE dt.BaseDate
        END

FROM #Seed s
JOIN #StreetNames sn ON sn.StreetID = s.StreetPick
JOIN #StreetTypes st ON st.StreetTypeID = s.StreetTypePick
JOIN #FirstNames f1 ON f1.FirstNameID = s.FirstPick1
JOIN #LastNames l1 ON l1.LastNameID = s.LastPick1
JOIN #FirstNames f2 ON f2.FirstNameID = s.FirstPick2
JOIN #LastNames l2 ON l2.LastNameID = s.LastPick2
CROSS APPLY (SELECT BaseAddress = CAST(s.HouseNumber AS VARCHAR(4)) + ' ' + sn.StreetName + ' ' + st.StreetType) addr
CROSS APPLY (SELECT BaseOwner  = f1.FirstName + ' ' + l1.LastName) owner1
CROSS APPLY (SELECT BaseOwner2 = f2.FirstName + ' ' + l2.LastName) owner2
CROSS APPLY (SELECT BaseDate   = CONVERT(VARCHAR(10), DATEADD(DAY, s.DaysOffset, '2000-01-01'), 120)) dt;
GO

DROP TABLE IF EXISTS #Seed;
DROP TABLE IF EXISTS #StreetNames;
DROP TABLE IF EXISTS #StreetTypes;
DROP TABLE IF EXISTS #FirstNames;
DROP TABLE IF EXISTS #LastNames;
GO

SELECT COUNT(*) AS NumRows FROM StagingPropertyOwnership;
GO
