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
-- other.
--
-- Step 2 is a retention/cleanup pass: deletes .bak files (full AND
-- differential -- xp_delete_file matches on extension, not naming
-- prefix, so one cleanup step covers both backup jobs' output) older
-- than 7 days from the default backup directory, using xp_delete_file --
-- the same mechanism SSMS's own Maintenance Cleanup Task uses under the
-- hood, not a hand-rolled file-deletion script.
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
    @job_name         = N'MunicipalAssessment - Full Backup',
    @step_id          = 1,
    @step_name        = N'Run full backup',
    @subsystem        = N'TSQL',
    @database_name    = N'MunicipalAssessment',
    @on_success_action = 3,  -- go to next step (the cleanup step), not quit
    @command          = N'
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

EXEC msdb.dbo.sp_add_jobstep
    @job_name      = N'MunicipalAssessment - Full Backup',
    @step_id       = 2,
    @step_name     = N'Clean up backups older than 7 days',
    @subsystem     = N'TSQL',
    @database_name = N'master',
    @command       = N'
DECLARE @BackupPath NVARCHAR(500) = CAST(SERVERPROPERTY(''InstanceDefaultBackupPath'') AS NVARCHAR(500));
IF RIGHT(@BackupPath, 1) <> ''\'' SET @BackupPath = @BackupPath + ''\'';

-- Computed fresh every time this step runs -- a rolling 7-day window,
-- not a fixed date baked in when the job was created.
DECLARE @CutoffDate DATETIME = DATEADD(DAY, -7, GETDATE());

-- xp_delete_file(file_type, folder_path, file_extension, older_than,
-- include_subfolders) -- file_type 0 = backup file, extension without
-- the leading dot. Matches on extension only, so this one step cleans
-- up both full (from this job) and differential (from the other backup
-- job) files sharing the same folder.
EXEC master.dbo.xp_delete_file 0, @BackupPath, N''bak'', @CutoffDate;
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
