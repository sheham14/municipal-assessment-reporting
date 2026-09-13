-- =============================================
-- Municipal Assessment & Tax Reporting
-- 02_create_tables.sql
--
-- Normalized schema (9 tables). Run after 01_create_database.sql.
-- Safe to re-run: drops tables first (in reverse FK-dependency order),
-- then recreates them (in FK-dependency order: referenced tables before
-- the tables that reference them).
--
-- No extra indexes here beyond what PK/UNIQUE constraints create
-- automatically. Indexes are added deliberately later, once real query
-- patterns exist (report procs / tuning exercise), each with a stated
-- reason -- not "indexed everything up front."
-- =============================================

USE MunicipalAssessment;
GO

-- ---------- Drop (reverse dependency order) ----------

DROP TABLE IF EXISTS Payment;
DROP TABLE IF EXISTS TaxBill;
DROP TABLE IF EXISTS TaxLevy;
DROP TABLE IF EXISTS Assessment;
DROP TABLE IF EXISTS PropertyOwner;
DROP TABLE IF EXISTS [Owner];
DROP TABLE IF EXISTS Property;
DROP TABLE IF EXISTS PropertyClass;
DROP TABLE IF EXISTS Ward;
GO

-- ---------- Lookup tables ----------

CREATE TABLE Ward (
    WardID     INT IDENTITY(1,1) NOT NULL,
    WardNumber TINYINT           NOT NULL,
    WardName   VARCHAR(50)       NOT NULL,
    CONSTRAINT PK_Ward PRIMARY KEY (WardID),
    CONSTRAINT UQ_Ward_WardNumber UNIQUE (WardNumber)
);
GO

CREATE TABLE PropertyClass (
    PropertyClassID INT IDENTITY(1,1) NOT NULL,
    ClassName        VARCHAR(50)       NOT NULL,
    CONSTRAINT PK_PropertyClass PRIMARY KEY (PropertyClassID),
    CONSTRAINT UQ_PropertyClass_ClassName UNIQUE (ClassName)
);
GO

-- ---------- Core entities ----------

CREATE TABLE Property (
    PropertyID      INT IDENTITY(1,1) NOT NULL,
    ParcelNumber    VARCHAR(20)       NOT NULL,
    AddressLine1    VARCHAR(100)      NOT NULL,
    UnitNumber      VARCHAR(10)       NULL,
    City            VARCHAR(50)       NOT NULL,
    PostalCode      VARCHAR(7)        NULL,
    WardID          INT               NOT NULL,
    PropertyClassID INT               NOT NULL,
    CONSTRAINT PK_Property PRIMARY KEY (PropertyID),
    CONSTRAINT UQ_Property_ParcelNumber UNIQUE (ParcelNumber),
    CONSTRAINT FK_Property_Ward FOREIGN KEY (WardID)
        REFERENCES Ward (WardID),
    CONSTRAINT FK_Property_PropertyClass FOREIGN KEY (PropertyClassID)
        REFERENCES PropertyClass (PropertyClassID)
);
GO

CREATE TABLE [Owner] (
    OwnerID        INT IDENTITY(1,1) NOT NULL,
    OwnerName      VARCHAR(100)      NOT NULL,
    MailingAddress VARCHAR(150)      NULL,
    CONSTRAINT PK_Owner PRIMARY KEY (OwnerID)
);
GO

-- Effective-dated many-to-many. A property can have more than one owner at
-- once (co-owners: two rows, same property, overlapping dates) and
-- ownership changes over time (old row gets EffectiveEndDate set, new row
-- inserted -- never UPDATE an ownership's identity in place). NULL
-- EffectiveEndDate means "still the current owner."
CREATE TABLE PropertyOwner (
    PropertyOwnerID    INT IDENTITY(1,1) NOT NULL,
    PropertyID         INT               NOT NULL,
    OwnerID             INT               NOT NULL,
    EffectiveStartDate DATE              NOT NULL,
    EffectiveEndDate   DATE              NULL,
    CONSTRAINT PK_PropertyOwner PRIMARY KEY (PropertyOwnerID),
    CONSTRAINT FK_PropertyOwner_Property FOREIGN KEY (PropertyID)
        REFERENCES Property (PropertyID),
    CONSTRAINT FK_PropertyOwner_Owner FOREIGN KEY (OwnerID)
        REFERENCES [Owner] (OwnerID),
    CONSTRAINT CK_PropertyOwner_DateRange CHECK (
        EffectiveEndDate IS NULL OR EffectiveEndDate > EffectiveStartDate
    )
);
GO

CREATE TABLE Assessment (
    AssessmentID   INT IDENTITY(1,1) NOT NULL,
    PropertyID     INT               NOT NULL,
    TaxYear        SMALLINT          NOT NULL,
    AssessedValue  DECIMAL(12,2)     NOT NULL,
    AssessmentDate DATE              NOT NULL,
    CONSTRAINT PK_Assessment PRIMARY KEY (AssessmentID),
    CONSTRAINT FK_Assessment_Property FOREIGN KEY (PropertyID)
        REFERENCES Property (PropertyID),
    -- One assessment per property per tax year -- documented simplifying
    -- assumption (see docs/decisions-log.md).
    CONSTRAINT UQ_Assessment_Property_TaxYear UNIQUE (PropertyID, TaxYear),
    CONSTRAINT CK_Assessment_AssessedValue CHECK (AssessedValue > 0)
);
GO

CREATE TABLE TaxLevy (
    TaxLevyID       INT IDENTITY(1,1) NOT NULL,
    PropertyClassID INT               NOT NULL,
    TaxYear         SMALLINT          NOT NULL,
    TaxRate         DECIMAL(9,6)      NOT NULL,
    CONSTRAINT PK_TaxLevy PRIMARY KEY (TaxLevyID),
    CONSTRAINT FK_TaxLevy_PropertyClass FOREIGN KEY (PropertyClassID)
        REFERENCES PropertyClass (PropertyClassID),
    CONSTRAINT UQ_TaxLevy_PropertyClass_TaxYear UNIQUE (PropertyClassID, TaxYear),
    CONSTRAINT CK_TaxLevy_TaxRate CHECK (TaxRate > 0)
);
GO

-- Historical snapshot, not a live calculation. AssessedValueUsed and
-- TaxRateUsed are copied in at bill-generation time and must never be
-- recalculated by joining back to Assessment/TaxLevy -- a reprinted bill
-- has to show what it said when it was issued, even if the assessment or
-- rate is corrected afterward.
CREATE TABLE TaxBill (
    TaxBillID         INT IDENTITY(1,1) NOT NULL,
    PropertyID        INT               NOT NULL,
    TaxYear           SMALLINT          NOT NULL,
    AssessedValueUsed DECIMAL(12,2)     NOT NULL,
    TaxRateUsed       DECIMAL(9,6)      NOT NULL,
    BillAmount        DECIMAL(12,2)     NOT NULL,
    BillDate          DATE              NOT NULL,
    DueDate           DATE              NOT NULL,
    CONSTRAINT PK_TaxBill PRIMARY KEY (TaxBillID),
    CONSTRAINT FK_TaxBill_Property FOREIGN KEY (PropertyID)
        REFERENCES Property (PropertyID),
    -- One bill per property per tax year -- documented simplifying
    -- assumption (see docs/decisions-log.md).
    CONSTRAINT UQ_TaxBill_Property_TaxYear UNIQUE (PropertyID, TaxYear),
    CONSTRAINT CK_TaxBill_BillAmount CHECK (BillAmount >= 0),
    CONSTRAINT CK_TaxBill_DueDate CHECK (DueDate >= BillDate)
);
GO

CREATE TABLE Payment (
    PaymentID     INT IDENTITY(1,1) NOT NULL,
    TaxBillID     INT               NOT NULL,
    PaymentDate   DATE              NOT NULL,
    PaymentAmount DECIMAL(12,2)     NOT NULL,
    -- Plain column, not a lookup table, by deliberate choice -- see
    -- docs/decisions-log.md (2026-09-11 entry).
    PaymentMethod VARCHAR(20)       NULL,
    CONSTRAINT PK_Payment PRIMARY KEY (PaymentID),
    CONSTRAINT FK_Payment_TaxBill FOREIGN KEY (TaxBillID)
        REFERENCES TaxBill (TaxBillID),
    CONSTRAINT CK_Payment_PaymentAmount CHECK (PaymentAmount > 0)
);
GO
