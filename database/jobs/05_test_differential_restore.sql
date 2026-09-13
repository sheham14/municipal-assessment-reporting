-- =============================================
-- Municipal Assessment & Tax Reporting
-- 05_test_differential_restore.sql
--
-- Proves the FULL + DIFFERENTIAL backup strategy is actually usable
-- together, not just that each backup job runs without error.
-- Restores to a third database (MunicipalAssessment_DiffRestoreTest) --
-- doesn't touch MunicipalAssessment or MunicipalAssessment_RestoreTest
-- (the full-only restore test from 02_test_restore.sql).
--
-- The restore sequence matters: the full backup must be restored
-- WITH NORECOVERY (leaves the database in a "restoring" state, able to
-- accept more backups on top of it) and only the LAST file in the
-- sequence uses WITH RECOVERY (brings the database online). Restoring
-- the full WITH RECOVERY by mistake would finalize the database
-- immediately and make it impossible to then apply the differential.
--
-- Finds the most recent full backup, then the most recent differential
-- taken *after* it (so they're actually a matched pair, not an
-- arbitrary full + an unrelated differential based on a different,
-- older full).
--
-- Run after both 01_backup_job.sql and 04_differential_backup_job.sql
-- have each produced at least one backup.
-- =============================================

USE master;
GO

DECLARE @FullBackupFile NVARCHAR(500);
DECLARE @FullBackupFinish DATETIME;

SELECT TOP 1 @FullBackupFile = mf.physical_device_name, @FullBackupFinish = bs.backup_finish_date
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = bs.media_set_id
WHERE bs.database_name = 'MunicipalAssessment' AND bs.type = 'D'
ORDER BY bs.backup_finish_date DESC;

DECLARE @DiffBackupFile NVARCHAR(500);

SELECT TOP 1 @DiffBackupFile = mf.physical_device_name
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = bs.media_set_id
WHERE bs.database_name = 'MunicipalAssessment' AND bs.type = 'I'
  AND bs.backup_finish_date >= @FullBackupFinish
ORDER BY bs.backup_finish_date DESC;

IF @FullBackupFile IS NULL OR @DiffBackupFile IS NULL
BEGIN
    RAISERROR('Need at least one full backup and one differential backup taken after it.', 16, 1);
    RETURN;
END

PRINT 'Full backup:         ' + @FullBackupFile;
PRINT 'Differential backup: ' + @DiffBackupFile;

DECLARE @DataPath NVARCHAR(500) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(500));
IF RIGHT(@DataPath, 1) <> '\' SET @DataPath = @DataPath + '\';

DECLARE @DataFile NVARCHAR(500) = @DataPath + N'MunicipalAssessment_DiffRestoreTest.mdf';
DECLARE @LogFile  NVARCHAR(500) = @DataPath + N'MunicipalAssessment_DiffRestoreTest_log.ldf';

IF DB_ID('MunicipalAssessment_DiffRestoreTest') IS NOT NULL
BEGIN
    ALTER DATABASE MunicipalAssessment_DiffRestoreTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MunicipalAssessment_DiffRestoreTest;
END

DECLARE @sql NVARCHAR(MAX) = N'
RESTORE DATABASE MunicipalAssessment_DiffRestoreTest
FROM DISK = ''' + @FullBackupFile + '''
WITH
    MOVE ''MunicipalAssessment''     TO ''' + @DataFile + ''',
    MOVE ''MunicipalAssessment_log'' TO ''' + @LogFile + ''',
    NORECOVERY, REPLACE, STATS = 10;';

EXEC sp_executesql @sql;

SET @sql = N'
RESTORE DATABASE MunicipalAssessment_DiffRestoreTest
FROM DISK = ''' + @DiffBackupFile + '''
WITH RECOVERY, STATS = 10;';

EXEC sp_executesql @sql;
GO

-- ---------- Verification: row counts, original vs. full+differential restore ----------

SELECT 'Ward' AS TableName,
    (SELECT COUNT(*) FROM MunicipalAssessment.dbo.Ward)                      AS OriginalCount,
    (SELECT COUNT(*) FROM MunicipalAssessment_DiffRestoreTest.dbo.Ward)      AS RestoredCount
UNION ALL
SELECT 'Property',
    (SELECT COUNT(*) FROM MunicipalAssessment.dbo.Property),
    (SELECT COUNT(*) FROM MunicipalAssessment_DiffRestoreTest.dbo.Property)
UNION ALL
SELECT 'Assessment',
    (SELECT COUNT(*) FROM MunicipalAssessment.dbo.Assessment),
    (SELECT COUNT(*) FROM MunicipalAssessment_DiffRestoreTest.dbo.Assessment)
UNION ALL
SELECT 'TaxBill',
    (SELECT COUNT(*) FROM MunicipalAssessment.dbo.TaxBill),
    (SELECT COUNT(*) FROM MunicipalAssessment_DiffRestoreTest.dbo.TaxBill)
UNION ALL
SELECT 'Payment',
    (SELECT COUNT(*) FROM MunicipalAssessment.dbo.Payment),
    (SELECT COUNT(*) FROM MunicipalAssessment_DiffRestoreTest.dbo.Payment);
GO
