-- =============================================
-- Municipal Assessment & Tax Reporting
-- 01_backup_job.sql
--
-- SQL Server Agent job: a full, compressed, checksummed backup of
-- MunicipalAssessment, on a nightly schedule. Writes to the instance's
-- own default backup directory (resolved at runtime via
-- SERVERPROPERTY('InstanceDefaultBackupPath'), not a hardcoded path) so
-- this script is portable across machines. Each run gets a
-- timestamped file name so successive backups don't overwrite each
-- other -- retention/cleanup of old backups is explicitly out of scope
-- (spec section 7).
--
-- Requires SQL Server Agent to be running.
-- =============================================

USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'MunicipalAssessment - Full Backup')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'MunicipalAssessment - Full Backup';
END
GO

EXEC msdb.dbo.sp_add_job
    @job_name   = N'MunicipalAssessment - Full Backup',
    @description = N'Nightly full backup of the MunicipalAssessment database.',
    @enabled    = 1;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name      = N'MunicipalAssessment - Full Backup',
    @step_name     = N'Run full backup',
    @subsystem     = N'TSQL',
    @database_name = N'MunicipalAssessment',
    @command       = N'
-- SERVERPROPERTY(''InstanceDefaultBackupPath'') does not include a
-- trailing backslash -- concatenating the file name directly onto it
-- produces an invalid path (e.g. "...MSSQL\BackupMyFile.bak" instead of
-- "...MSSQL\Backup\MyFile.bak"). Add the separator explicitly rather
-- than assuming.
DECLARE @BackupPath NVARCHAR(500) = CAST(SERVERPROPERTY(''InstanceDefaultBackupPath'') AS NVARCHAR(500));
IF RIGHT(@BackupPath, 1) <> ''\'' SET @BackupPath = @BackupPath + ''\'';

DECLARE @BackupFile NVARCHAR(500) = @BackupPath + N''MunicipalAssessment_'' + CONVERT(NVARCHAR(8), GETDATE(), 112)
    + N''_'' + REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), '':'', '''') + N''.bak'';

BACKUP DATABASE MunicipalAssessment
TO DISK = @BackupFile
WITH INIT, COMPRESSION, CHECKSUM, STATS = 10;
';
GO

EXEC msdb.dbo.sp_add_schedule
    @schedule_name    = N'Nightly at 1 AM',
    @freq_type        = 4,      -- daily
    @freq_interval    = 1,      -- every 1 day
    @active_start_time = 010000; -- 01:00:00
GO

EXEC msdb.dbo.sp_attach_schedule
    @job_name      = N'MunicipalAssessment - Full Backup',
    @schedule_name = N'Nightly at 1 AM';
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'MunicipalAssessment - Full Backup';
GO
