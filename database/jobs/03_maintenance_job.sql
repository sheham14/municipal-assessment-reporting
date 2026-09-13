-- =============================================
-- Municipal Assessment & Tax Reporting
-- 03_maintenance_job.sql
--
-- SQL Server Agent job: weekly index maintenance based on MEASURED
-- fragmentation, not a blanket rebuild of everything.
--
--   5% <= fragmentation < 30%  -> REORGANIZE (cheaper, online, just
--                                  defragments leaf-level pages)
--   fragmentation >= 30%       -> REBUILD (more expensive, rebuilds the
--                                  whole index, also refreshes its
--                                  statistics as a side effect)
--   fragmentation < 5%         -> left alone entirely
--
-- Indexes under 100 pages are skipped -- fragmentation on a tiny index
-- doesn't meaningfully affect performance, and rebuilding it is pure
-- overhead. Same "deliberate, not indexed/maintained everything"
-- philosophy as the schema's indexing itself.
--
-- sp_updatestats runs afterward regardless of which path each index
-- took: REBUILD already refreshes statistics with a full scan, but
-- REORGANIZE does not, so a uniform statistics update afterward covers
-- every index consistently either way.
--
-- Requires SQL Server Agent to be running.
-- =============================================

USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'MunicipalAssessment - Index and Statistics Maintenance')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'MunicipalAssessment - Index and Statistics Maintenance';
END
GO

EXEC msdb.dbo.sp_add_job
    @job_name    = N'MunicipalAssessment - Index and Statistics Maintenance',
    @description = N'Weekly index rebuild/reorganize (based on measured fragmentation) and statistics update for MunicipalAssessment.',
    @enabled     = 1;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name      = N'MunicipalAssessment - Index and Statistics Maintenance',
    @step_name     = N'Rebuild/reorganize indexes and update statistics',
    @subsystem     = N'TSQL',
    @database_name = N'MunicipalAssessment',
    @command       = N'
DECLARE @SchemaName SYSNAME, @TableName SYSNAME, @IndexName SYSNAME, @Frag FLOAT, @SQL NVARCHAR(MAX);

DECLARE index_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT s.name, t.name, i.name, ps.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
JOIN sys.tables t ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE i.name IS NOT NULL
  AND ps.page_count > 100
  AND ps.avg_fragmentation_in_percent >= 5.0;

OPEN index_cursor;
FETCH NEXT FROM index_cursor INTO @SchemaName, @TableName, @IndexName, @Frag;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @Frag >= 30.0
        SET @SQL = N''ALTER INDEX '' + QUOTENAME(@IndexName) + N'' ON '' + QUOTENAME(@SchemaName) + N''.'' + QUOTENAME(@TableName) + N'' REBUILD;'';
    ELSE
        SET @SQL = N''ALTER INDEX '' + QUOTENAME(@IndexName) + N'' ON '' + QUOTENAME(@SchemaName) + N''.'' + QUOTENAME(@TableName) + N'' REORGANIZE;'';

    EXEC sp_executesql @SQL;

    FETCH NEXT FROM index_cursor INTO @SchemaName, @TableName, @IndexName, @Frag;
END

CLOSE index_cursor;
DEALLOCATE index_cursor;

EXEC sp_updatestats;
';
GO

EXEC msdb.dbo.sp_add_schedule
    @schedule_name          = N'Weekly Sunday 2 AM',
    @freq_type              = 8,  -- weekly
    @freq_interval          = 1,  -- Sunday (bitmask: 1=Sun,2=Mon,4=Tue,...)
    @freq_recurrence_factor = 1,  -- every 1 week
    @active_start_time      = 020000; -- 02:00:00
GO

EXEC msdb.dbo.sp_attach_schedule
    @job_name      = N'MunicipalAssessment - Index and Statistics Maintenance',
    @schedule_name = N'Weekly Sunday 2 AM';
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'MunicipalAssessment - Index and Statistics Maintenance';
GO
