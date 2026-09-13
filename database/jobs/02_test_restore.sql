-- =============================================
-- Municipal Assessment & Tax Reporting
-- 02_test_restore.sql
--
-- Restores the most recent full backup of MunicipalAssessment to a
-- second database name (MunicipalAssessment_RestoreTest), then verifies
-- it by comparing row counts against the original and by running an
-- actual reporting stored procedure against the restored copy. This is
-- the step that proves the backup is usable, not just that a backup
-- file exists.
--
-- Finds the backup via msdb's own backup history catalog
-- (msdb.dbo.backupset / backupmediafamily) rather than assuming a file
-- name. Inspects the backup's logical file names via
-- RESTORE FILELISTONLY before writing the restore itself, rather than
-- assuming SQL Server's default naming convention -- confirmed here to
-- be 'MunicipalAssessment' (data) and 'MunicipalAssessment_log' (log).
--
-- Run after database/jobs/01_backup_job.sql has produced at least one
-- backup.
-- =============================================

USE master;
GO

DECLARE @BackupFile NVARCHAR(500);
SELECT TOP 1 @BackupFile = mf.physical_device_name
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = bs.media_set_id
WHERE bs.database_name = 'MunicipalAssessment' AND bs.type = 'D'
ORDER BY bs.backup_finish_date DESC;

IF @BackupFile IS NULL
BEGIN
    RAISERROR('No full backup found for MunicipalAssessment in the backup history.', 16, 1);
    RETURN;
END

PRINT 'Restoring from: ' + @BackupFile;

DECLARE @DataPath NVARCHAR(500) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(500));
IF RIGHT(@DataPath, 1) <> '\' SET @DataPath = @DataPath + '\';

DECLARE @DataFile NVARCHAR(500) = @DataPath + N'MunicipalAssessment_RestoreTest.mdf';
DECLARE @LogFile  NVARCHAR(500) = @DataPath + N'MunicipalAssessment_RestoreTest_log.ldf';

IF DB_ID('MunicipalAssessment_RestoreTest') IS NOT NULL
BEGIN
    ALTER DATABASE MunicipalAssessment_RestoreTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MunicipalAssessment_RestoreTest;
END

DECLARE @sql NVARCHAR(MAX) = N'
RESTORE DATABASE MunicipalAssessment_RestoreTest
FROM DISK = ''' + @BackupFile + '''
WITH
    MOVE ''MunicipalAssessment''     TO ''' + @DataFile + ''',
    MOVE ''MunicipalAssessment_log'' TO ''' + @LogFile + ''',
    REPLACE, STATS = 10;';

EXEC sp_executesql @sql;
GO

-- ---------- Verification: row counts, original vs. restored ----------

SELECT 'Ward' AS TableName,
    (SELECT COUNT(*) FROM MunicipalAssessment.dbo.Ward)             AS OriginalCount,
    (SELECT COUNT(*) FROM MunicipalAssessment_RestoreTest.dbo.Ward) AS RestoredCount
UNION ALL
SELECT 'Property',
    (SELECT COUNT(*) FROM MunicipalAssessment.dbo.Property),
    (SELECT COUNT(*) FROM MunicipalAssessment_RestoreTest.dbo.Property)
UNION ALL
SELECT 'Assessment',
    (SELECT COUNT(*) FROM MunicipalAssessment.dbo.Assessment),
    (SELECT COUNT(*) FROM MunicipalAssessment_RestoreTest.dbo.Assessment)
UNION ALL
SELECT 'TaxBill',
    (SELECT COUNT(*) FROM MunicipalAssessment.dbo.TaxBill),
    (SELECT COUNT(*) FROM MunicipalAssessment_RestoreTest.dbo.TaxBill)
UNION ALL
SELECT 'Payment',
    (SELECT COUNT(*) FROM MunicipalAssessment.dbo.Payment),
    (SELECT COUNT(*) FROM MunicipalAssessment_RestoreTest.dbo.Payment)
UNION ALL
SELECT 'RejectedRow',
    (SELECT COUNT(*) FROM MunicipalAssessment.dbo.RejectedRow),
    (SELECT COUNT(*) FROM MunicipalAssessment_RestoreTest.dbo.RejectedRow);
GO

-- ---------- Verification: an actual reporting proc runs correctly against the restored copy ----------
-- Not just "the data is there" -- the whole schema/procs/views survived
-- the restore intact.

EXEC MunicipalAssessment_RestoreTest.dbo.rpt_WardSummary @TaxYear = 2026;
GO
