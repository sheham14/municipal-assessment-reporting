-- =============================================
-- Municipal Assessment & Tax Reporting
-- 01_create_staging_tables.sql
--
-- Staging tables for raw, deliberately messy synthetic data. Loosely typed
-- on purpose (VARCHAR even for numbers/dates) so garbage values can be
-- inserted without failing -- validation and rejection happen later, in
-- the transform step, where failures can be examined and logged instead
-- of just blocking the insert.
--
-- Ward, PropertyClass, and TaxLevy are NOT staged here -- they're small,
-- controlled reference lists we define ourselves, not messy source data.
-- They're seeded directly into the real tables (see database/staging/
-- 02_seed_reference_data.sql). See docs/decisions-log.md.
--
-- Run after database/schema/02_create_tables.sql.
-- =============================================

USE MunicipalAssessment;
GO

DROP TABLE IF EXISTS StagingPayment;
DROP TABLE IF EXISTS StagingAssessment;
DROP TABLE IF EXISTS StagingPropertyOwnership;
GO

-- Wide, denormalized raw extract -- one row per parcel, owner fields
-- un-split, ward/class as free text rather than FKs. This is what a real
-- property roll export tends to look like before anyone normalizes it.
CREATE TABLE StagingPropertyOwnership (
    StagingID           INT IDENTITY(1,1) NOT NULL,
    ParcelNumber        VARCHAR(20)        NULL,
    AddressLine1        VARCHAR(150)       NULL,
    UnitNumber          VARCHAR(20)        NULL,
    City                VARCHAR(50)        NULL,
    PostalCode          VARCHAR(15)        NULL,
    WardName            VARCHAR(50)        NULL,
    PropertyClassName   VARCHAR(50)        NULL,
    PrimaryOwnerName    VARCHAR(150)       NULL,
    SecondaryOwnerName  VARCHAR(150)       NULL,
    OwnershipStartDate  VARCHAR(20)        NULL,
    LoadedAt            DATETIME2          NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_StagingPropertyOwnership PRIMARY KEY (StagingID)
);
GO

-- One row per property per tax year. ParcelNumber is free text here, not
-- a FK -- some rows deliberately won't match anything in
-- StagingPropertyOwnership (orphans), and some AssessedValue/
-- AssessmentDate values will be deliberately malformed.
CREATE TABLE StagingAssessment (
    StagingID       INT IDENTITY(1,1) NOT NULL,
    ParcelNumber    VARCHAR(20)        NULL,
    TaxYear         SMALLINT           NULL,
    AssessedValue   VARCHAR(20)        NULL,
    AssessmentDate  VARCHAR(20)        NULL,
    LoadedAt        DATETIME2          NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_StagingAssessment PRIMARY KEY (StagingID)
);
GO

-- One row per payment. Resolved to a TaxBill in transform by joining
-- ParcelNumber + TaxYear -- some rows deliberately won't resolve
-- (orphans: a payment against a parcel/year with no matching bill).
CREATE TABLE StagingPayment (
    StagingID      INT IDENTITY(1,1) NOT NULL,
    ParcelNumber   VARCHAR(20)        NULL,
    TaxYear        SMALLINT           NULL,
    PaymentDate    VARCHAR(20)        NULL,
    PaymentAmount  VARCHAR(20)        NULL,
    PaymentMethod  VARCHAR(20)        NULL,
    LoadedAt       DATETIME2          NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_StagingPayment PRIMARY KEY (StagingID)
);
GO
