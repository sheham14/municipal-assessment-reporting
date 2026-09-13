# Decisions Log

Running notes on design decisions and assumptions made during the build, captured as they happen so the README (step 13) can be written from this instead of from memory.

---

**2026-09-11 — `PaymentMethod` stays a plain column, not a lookup table**

Considered normalizing `Payment.PaymentMethod` into a `PaymentMethod` lookup table, same pattern as `Ward` and `PropertyClass` — this was the user's own observation while reviewing the schema, not something prompted.

Decision: kept it as a plain `VARCHAR(20)` column.

Reasoning: the spec (section 3) explicitly scopes the schema to nine named tables and `PaymentMethod` isn't one of them. `Ward` and `PropertyClass` justify their own tables because they're load-bearing — they drive FK relationships and feed Report 1's grouping directly. `PaymentMethod` is a descriptive tag that doesn't participate in any of the three required reports' logic, so normalizing it wouldn't demonstrate anything the schema doesn't already demonstrate via Ward/PropertyClass.

Status: deliberately deferred, not a gap. Candidate for a Tier 3 polish item if time allows.

---

**2026-09-11 — `Ward`, `PropertyClass`, `TaxLevy` are seeded directly, not staged**

Decision: these three tables are populated with plain `INSERT` statements straight into the real tables, skipping the staging/transform path used for everything else.

Reasoning: the spec's data-defect list (inconsistent casing, nulls in optional fields, duplicate/near-duplicate names, orphan records, malformed values) is about messy *source* data — properties, owners, assessments, payments. `Ward`, `PropertyClass`, and `TaxLevy` are small, controlled reference lists we're defining ourselves (a handful of wards, a handful of classes, one rate per class per year) — there's no external "raw extract" for them to be messy in the first place, so running them through a staging/transform pipeline would be theater, not real ETL work.

Status: scoping decision, not an oversight.

---

**2026-09-11 — Ward names are real; everything else stays synthetic**

The user is applying to the City of St. John's specifically and wanted to personalize the project by using real city data. Considered replicating more of the real system (real ward names, real published tax rates) but decided against most of it.

Decision: `Ward` uses the real City of St. John's ward structure — 5 wards, numbered "Ward 1" through "Ward 5" (verified against the St. John's City Council Wikipedia page, cross-checked with a direct page fetch after the initial web search summary hallucinated a councillor name that doesn't exist — a useful reminder to verify AI search summaries against the primary source before trusting specific facts). No real councillor or other named-individual data was pulled in; it isn't needed by the schema. `PropertyClass` and `TaxLevy` (rates) remain entirely synthetic, as do all addresses, owner names, and business rules (arrears/aging logic, payment allocation, etc.).

Reasoning: ward names are public administrative geography, not a claim about business-rule accuracy, so using the real ones is low-risk personalization. Real tax rates and real business logic were rejected because they invite exactly the failure mode the original framing constraint (spec section 1) was written to avoid — presenting invented aging/arrears/payment logic as if it reflected the real system, in front of people who would actually know the real rules. Getting real rates accurately also cost research time not worth spending under the deadline.

Status: deliberate, partial use of real data. README must still carry the "synthetic practice model" framing statement — this doesn't change that, it just explains the one real element.

---

**2026-09-11 — Three SQL Server gotchas hit (and fixed) while writing the property data generator**

Building `database/staging/03_generate_property_data.sql` (the ~50,000-row synthetic property/owner generator) surfaced three real bugs worth remembering, all specific to generating randomized test data at scale in T-SQL:

1. **`CROSS APPLY (SELECT TOP 1 x FROM t ORDER BY NEWID())` silently loses randomness.** Used to pick a random street/first name/last name per row. Verified after the fact that `PrimaryOwnerName` had only 2 distinct values across 50,000 rows — the optimizer treated the uncorrelated subquery as effectively constant and reused one cached pick across large stretches of rows instead of drawing fresh per row. Caught by checking `COUNT(DISTINCT ...)` after generation, not by the script erroring.

2. **`ABS(CHECKSUM(NEWID()))` overflows.** `CHECKSUM(NEWID())` returns an `INT`, and `INT`'s minimum value has no positive `INT` representation, so `ABS()` on that specific (rare, ~1-in-4-billion) value throws `Msg 8115, Arithmetic overflow error`. Hit this on a rerun after fixing #1, purely by chance, out of hundreds of thousands of random draws. Fix: cast to `BIGINT` before `ABS()`.

3. **Combining `GENERATE_SERIES` + a `CROSS APPLY` computing `NEWID()`-based values + immediately joining that same derived table to lookup tables, all in one statement, produced a runaway parallel execution plan** — confirmed via `sys.dm_exec_requests` (joined to `sys.dm_exec_sql_text`) showing the session stuck on `CXCONSUMER` waits with over 20 minutes of CPU time accumulated for a job that should take seconds. Killed the session with `KILL <session_id>` and restructured the generator into two phases: materialize every random draw into a plain temp table first (no joins), then join that now-ordinary, concrete-valued temp table to the lookup tables in a separate, simple statement. Fixed it completely (3 seconds for 50,000 rows).

Why this is worth keeping: this is a legitimate "diagnose a stuck query" story using the actual DMVs a working DBA would reach for, not a toy example — good material for the interview, and a reminder to verify generated test data's actual distribution rather than assuming the SQL did what it looks like it should do.

---

**2026-09-11 — Owner de-duplication is by normalized name only, a known limitation, not an oversight**

The transform resolves `Owner` identity by normalizing casing/whitespace and matching on the cleaned name string (this is also how near-duplicate owner names, one of the spec's required defects, get collapsed into one `Owner` row). The user asked, correctly, what happens when two genuinely different owners happen to share an identical name.

Decision: keep name-based matching as designed. Do not build a stronger identity-resolution mechanism.

Reasoning: name alone can never fully solve this in any system — two distinct real people named identically are indistinguishable from one person appearing twice if a name string is all you have. Real systems avoid the problem entirely by assigning an owner ID at intake (when a deed is registered) and treating the name as a display field, not an identifier. Building that here would be real scope creep for a 2-day project, and would mean fabricating some kind of synthetic owner ID with no source data to justify it. Since every owner in this dataset is fully synthetic, an occasional coincidental name collision causes no real-world harm the way it would in a live system merging two real taxpayers.

Status: deliberate, documented limitation. Must appear in the README's Assumptions section: "Owner identity is resolved by normalized name matching, not a persistent owner ID. Two distinct real owners who happened to share an identical cleaned name would be incorrectly merged into one Owner row. Production systems avoid this by assigning an owner ID at intake rather than deriving identity from name text."

---

**2026-09-11 — TaxBill due-date offset was a data-modeling bug, not a SQL bug: caught by checking report OUTPUT, not just query correctness**

The original TaxBill assumption was `BillDate = AssessmentDate + 14 days`, `DueDate = BillDate + 60 days`. The SQL ran fine, `rpt_ArrearsAging` executed without error and returned data. But when the bucket distribution was actually checked, all 71,315 outstanding bills landed in a single bucket, "90+ Days" — zero variety, which defeats the entire purpose of Report 3.

Root cause: `AssessmentDate` always falls in Jan-Mar (by generator design). A 14-day offset put every `DueDate` in Mar-Jun regardless of tax year, so even 2026 (the most recent year) was already 3-6 months overdue by "today" (2026-09-11) — there was no tax year whose bills could possibly land anywhere but deep in arrears.

Fix: changed the offset to `BillDate = AssessmentDate + 110 days`, `DueDate = AssessmentDate + 170 days`. This isn't just a number tweaked to make a demo look nice — bills mailed mid-year with a summer/fall due date is a real, common municipal pattern (assessment finalized early in the year, billing and administration mid-year). With this offset, 2026's due dates land March-June *of the following cycle relative to the assessment*, straddling "today," which naturally spreads that year's unpaid bills across Current/1-30/31-60/61-90 while older tax years (2022-2025) correctly land entirely in 90+ (that debt genuinely is old — this is correct, not a defect).

Why this is worth keeping: the query never errored — the bug was entirely in the data's business-logic correctness, invisible unless you actually look at the distribution of the output rather than just confirming the SQL executes. Good interview material for "how do you verify your work" beyond "the report ran."

---

**2026-09-12 — Database reporting role verified with a negative test, not just a positive one**

Built `ReportingRole` (spec section 6): a dedicated SQL login (`ssrs_reporting_svc`) granted `EXECUTE` on the 5 reporting stored procedures and `SELECT` on the 2 reporting views, nothing on the 9 base tables or the staging/`RejectedRow` tables.

Verified by connecting to SQL Server *as that login* (`sqlcmd -U ssrs_reporting_svc`) and confirming four things, not just that the grants ran without error: it can execute `rpt_WardSummary`, it can `SELECT` from `vw_CurrentPropertyOwnership`, it gets `Msg 229` (permission denied) trying to `SELECT * FROM Property`, and the same denial on `RejectedRow`. All four came back exactly as expected.

Why this matters: "I granted the right permissions" and "I proved the wrong permissions don't work" are different claims — the second one is what least privilege actually means, and it's the more defensible thing to say in an interview than just describing the GRANT statements.

---

**2026-09-12 — Slow report loads traced to OS-level resource contention, not the new SQL login**

Right after switching the shared data source to the new `ssrs_reporting_svc` SQL login, reports became extremely slow to load. The obvious suspect was the credential change. Ruled that out directly: timed a plain `sqlcmd` connection with Windows Authentication too, and it timed out identically (`Login timeout expired`, `Shared Memory Provider: Timeout error`) — so the failure mode was identical regardless of auth method, which meant it wasn't about the login at all.

Checked the actual SQL Server process (`Get-Process sqlservr`): near-zero CPU, 233MB memory — completely healthy. Checked the top CPU-consuming processes on the machine instead and found Chrome, Visual Studio, two ChatGPT instances, three VS Code windows, and SSMS all running simultaneously with heavy cumulative CPU usage. SQL Server's connection-handling thread was almost certainly being starved of CPU time by everything else running at once, not failing on its own. One test that was allowed to keep running actually succeeded, with correct data, after 1 minute 47 seconds — confirming "severely delayed" rather than "broken." Closing unnecessary applications brought the same query back to 0.4 seconds.

Why this matters: the fix wasn't a database change at all — the database was never the problem. This is a good demonstration of the diagnostic habit that actually matters in SQL Server administration: check whether the *database engine* is unhealthy before assuming the problem is inside it, since the same symptom (slow/failed connections) can come from something entirely outside the database.

---

**2026-09-13 — SSRS file-share subscription: two real infrastructure requirements, not just SSRS configuration**

Setting up the scheduled subscription on Report 1 surfaced two things worth remembering, neither of which is really about SSRS itself:

1. **Windows File Share delivery requires a true UNC path** (`\\ComputerName\ShareName\...`) — a local drive path like `C:\Users\...` is rejected outright ("must conform to Uniform Naming Convention"), even though the target is the same machine as the report server. Fixed by creating an actual SMB share (`New-SmbShare`, run elevated) pointing at a `subscription-output/` folder and using `\\OMEN\SSRSSubscriptions` instead.
2. **Unattended file delivery needs real Windows credentials**, and the signed-in user only had a PIN, not a known password. Rather than chase down a Microsoft-account password, created a small dedicated local account (`ssrs_filedelivery`) with `New-LocalUser`, granted it `Modify` NTFS rights on the output folder specifically (share-level "Everyone: Full Control" alone isn't sufficient — the underlying file-system ACL has to allow it too), and used that account's credentials in the subscription. This is also the more correct pattern for a real deployment anyway — a scheduled service should run under its own dedicated account, not someone's personal login.

Both `New-SmbShare` and `New-LocalUser` require elevated (admin) PowerShell — attempted first without elevation to confirm that was really the blocker before asking the user to re-run elevated, rather than assuming. Also hit PowerShell's default script-execution policy blocking the setup script entirely ("running scripts is disabled on this system") even while running as administrator — `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` fixed it for just that one window, without changing any permanent system policy.

Verified the whole chain end-to-end rather than trusting "subscription created" as proof: polled `ReportServer.dbo.Subscriptions.LastRunTime` until the schedule fired, then confirmed a real 109KB PDF actually appeared in the output folder with a matching timestamp and a "file has been saved" status message.

---

**2026-09-12 — Backup job failed on the first run: missing path separator, not a permissions problem**

First run of the backup Agent job failed with `Access is denied` trying to open `...MSSQL\BackupMunicipalAssessment_20260912_064310.bak`. Read the path literally instead of assuming it was a real permissions issue: there's no `\` between `Backup` (the folder) and the filename. `SERVERPROPERTY('InstanceDefaultBackupPath')` doesn't include a trailing backslash, and the script concatenated the timestamped filename directly onto it, producing a path that resolved to a nonexistent location one folder up from where the account actually has write access — hence "access denied," even though the real problem was a malformed path, not a permission grant.

Fixed by checking for and adding the separator explicitly (`IF RIGHT(@BackupPath,1) <> '\' SET @BackupPath = @BackupPath + '\'`) rather than assuming either convention. Reran successfully: 10,946 pages backed up in 0.65 seconds.

Why this matters: the error message's literal wording ("Access is denied") pointed at the wrong layer at first glance. Reading the exact failing path character-by-character rather than pattern-matching the error to "must be a permissions issue" found the real bug faster.

---

**2026-09-12 — Maintenance job: verified it runs in the right database, and that "did nothing" was the correct outcome**

The maintenance job (index reorganize/rebuild by measured fragmentation, then `sp_updatestats`) reports success but its job history mentions tables like `sys.plan_persist_query` and `sys.db_ledger_blocks`, which look like `msdb` system tables at a glance. Verified directly rather than assuming a bug: temporarily replaced the job step with `PRINT 'DB context is: ' + DB_NAME();` and reran it — confirmed it genuinely executes inside `MunicipalAssessment`, not `msdb`. The tables in question are internal Query Store/Ledger system tables that exist in the `sys` schema of every database, not `msdb`-specific ones — a case of a name looking suspicious without actually being wrong.

Separately checked actual fragmentation on every real index (`sys.dm_db_index_physical_stats`): the worst was 3.3% (`PropertyOwner`), everything else under that — all comfortably below the 5% threshold that triggers any action. Correct and expected for a database built entirely from fresh bulk inserts. The job finding nothing to do isn't a failure to demonstrate — it's the threshold logic working exactly as intended, not being needlessly aggressive against healthy indexes.
