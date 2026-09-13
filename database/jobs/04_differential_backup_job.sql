-- =============================================
-- Municipal Assessment & Tax Reporting
-- 04_differential_backup_job.sql
--
-- SQL Server Agent job: a differential backup of MunicipalAssessment
-- every 4 hours, starting at 5 AM (after the nightly 1 AM full backup
-- from 01_backup_job.sql, so the first differential of the day always
-- has a same-day full backup as its base).
--
-- A differential backup captures everything changed since the last FULL
-- backup (not since the last differential) -- so restoring requires
-- exactly one full + the single most recent differential, not a chain
-- of every differential taken since. That's the whole point: cheaper
-- and faster than another full backup, without the multi-file chain
-- fragility of transaction log backups.
--
-- Filename uses a DIFF_ prefix specifically so 01_backup_job.sql's
-- retention cleanup step (which matches on the .bak extension, not
-- naming pattern) cleans up both jobs' output uniformly from the same
-- folder, and so it's visually obvious in the backup directory which
-- file is which type.
--
-- Requires SQL Server Agent to be running, and at least one full backup
-- to already exist (a differential with no preceding full backup fails).
-- =============================================

USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'MunicipalAssessment - Differential Backup')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'MunicipalAssessment - Differential Backup';
END
GO

EXEC msdb.dbo.sp_add_job
    @job_name    = N'MunicipalAssessment - Differential Backup',
    @description = N'Differential backup of MunicipalAssessment every 4 hours, between full backups.',
    @enabled     = 1;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name      = N'MunicipalAssessment - Differential Backup',
    @step_name     = N'Run differential backup',
    @subsystem     = N'TSQL',
    @database_name = N'MunicipalAssessment',
    @command       = N'
DECLARE @BackupPath NVARCHAR(500) = CAST(SERVERPROPERTY(''InstanceDefaultBackupPath'') AS NVARCHAR(500));
IF RIGHT(@BackupPath, 1) <> ''\'' SET @BackupPath = @BackupPath + ''\'';

DECLARE @BackupFile NVARCHAR(500) = @BackupPath + N''MunicipalAssessment_DIFF_'' + CONVERT(NVARCHAR(8), GETDATE(), 112)
    + N''_'' + REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), '':'', '''') + N''.bak'';

BACKUP DATABASE MunicipalAssessment
TO DISK = @BackupFile
WITH DIFFERENTIAL, COMPRESSION, CHECKSUM, STATS = 10;
';
GO

EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'Every 4 hours from 5 AM',
    @freq_type            = 4,      -- daily
    @freq_interval        = 1,      -- every day
    @freq_subday_type     = 8,      -- subday units = hours
    @freq_subday_interval = 4,      -- every 4 hours
    @active_start_time    = 050000, -- starting at 05:00:00
    @active_end_time      = 235900; -- through 23:59:00, so it doesn't run into the 1 AM full backup window
GO

EXEC msdb.dbo.sp_attach_schedule
    @job_name      = N'MunicipalAssessment - Differential Backup',
    @schedule_name = N'Every 4 hours from 5 AM';
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'MunicipalAssessment - Differential Backup';
GO
