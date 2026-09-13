-- =============================================
-- Municipal Assessment & Tax Reporting
-- 02_seed_reference_data.sql
--
-- Seeds Ward, PropertyClass, and TaxLevy directly -- no staging/transform
-- for these, see docs/decisions-log.md. Run after
-- database/schema/02_create_tables.sql.
--
-- Ward names/numbers are the one deliberately real element in this
-- project: the City of St. John's has 5 wards, numbered Ward 1-5
-- (verified against the St. John's City Council Wikipedia page). Property
-- classes and tax rates below are entirely synthetic -- see
-- docs/decisions-log.md.
--
-- Clears and reseeds the three tables, so this is safe to re-run *before*
-- any downstream table (Property, Assessment, ...) references these rows.
-- If it's run after downstream data exists, the DELETEs below will fail
-- on the foreign key constraint rather than silently orphan anything --
-- rebuild from the schema scripts forward in that case.
-- =============================================

USE MunicipalAssessment;
GO

DELETE FROM TaxLevy;
DELETE FROM PropertyClass;
DELETE FROM Ward;
GO

-- ---------- Ward (real) ----------

INSERT INTO Ward (WardNumber, WardName) VALUES
    (1, 'Ward 1'),
    (2, 'Ward 2'),
    (3, 'Ward 3'),
    (4, 'Ward 4'),
    (5, 'Ward 5');
GO

-- ---------- PropertyClass (synthetic) ----------

INSERT INTO PropertyClass (ClassName) VALUES
    ('Residential'),
    ('Commercial'),
    ('Industrial'),
    ('Vacant Land'),
    ('Institutional');
GO

-- ---------- TaxLevy (synthetic, 5 classes x 5 tax years) ----------
-- VALUES here is an inline table -- a temporary table literal that exists
-- only for this statement. Joining it to PropertyClass by ClassName
-- resolves the real PropertyClassID without hardcoding IDENTITY values.

INSERT INTO TaxLevy (PropertyClassID, TaxYear, TaxRate)
SELECT pc.PropertyClassID, v.TaxYear, v.TaxRate
FROM (VALUES
    ('Residential',   2022, 0.010000),
    ('Residential',   2023, 0.010500),
    ('Residential',   2024, 0.010800),
    ('Residential',   2025, 0.011000),
    ('Residential',   2026, 0.011200),
    ('Commercial',    2022, 0.018000),
    ('Commercial',    2023, 0.018200),
    ('Commercial',    2024, 0.018500),
    ('Commercial',    2025, 0.018800),
    ('Commercial',    2026, 0.019000),
    ('Industrial',    2022, 0.020000),
    ('Industrial',    2023, 0.020300),
    ('Industrial',    2024, 0.020500),
    ('Industrial',    2025, 0.020800),
    ('Industrial',    2026, 0.021000),
    ('Vacant Land',   2022, 0.008000),
    ('Vacant Land',   2023, 0.008200),
    ('Vacant Land',   2024, 0.008400),
    ('Vacant Land',   2025, 0.008600),
    ('Vacant Land',   2026, 0.008800),
    ('Institutional', 2022, 0.006000),
    ('Institutional', 2023, 0.006100),
    ('Institutional', 2024, 0.006200),
    ('Institutional', 2025, 0.006300),
    ('Institutional', 2026, 0.006400)
) AS v(ClassName, TaxYear, TaxRate)
JOIN PropertyClass pc ON pc.ClassName = v.ClassName;
GO
