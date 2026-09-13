-- =============================================
-- Municipal Assessment & Tax Reporting
-- 01_create_transform_objects.sql
--
-- RejectedRow: a generic log for every row the transform rejects, from
-- any source table, with a reason. "Rejections should be logged, not
-- silently dropped" (spec section 2).
--
-- Run after database/staging/*.sql (all three data generation scripts).
-- =============================================

USE MunicipalAssessment;
GO

DROP TABLE IF EXISTS RejectedRow;
GO

CREATE TABLE RejectedRow (
    RejectedRowID   INT IDENTITY(1,1) NOT NULL,
    SourceTable     VARCHAR(50)       NOT NULL,
    SourceKey       VARCHAR(100)      NULL,
    RejectionReason VARCHAR(200)      NOT NULL,
    RawData         VARCHAR(500)      NULL,
    RejectedAt      DATETIME2         NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_RejectedRow PRIMARY KEY (RejectedRowID)
);
GO
