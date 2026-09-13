# Environment Setup Log — SQL Server / SSRS Build

**Status: Milestone 1 complete.** Report server accepts deployments and serves reports to a browser.

---

## What is installed

| Component | Version / Edition | Notes |
|---|---|---|
| SQL Server Database Engine | 2022, **Evaluation** edition, instance `MSSQLSERVER` | Expires after 180 days. Fine for this project. |
| SQL Server Management Studio | SSMS 22, Core Components only | No optional workloads installed. |
| SQL Server Reporting Services | 2022 (16.0.1118.33), instance `SSRS` | Separate installer from the engine. |
| Visual Studio | 2022 Community + *Data storage and processing* workload | Plus **Microsoft Reporting Services Projects** extension. |

**Machine name:** `OMEN`. Server name for all connections is `OMEN` or `localhost` (interchangeable, since this is the default instance).

## What is configured

- **Web Service URL** — `http://omen/ReportServer`
- **Report server database** — `ReportServer` + `ReportServerTempDB`, created on the `OMEN` instance
- **Web Portal URL** — `http://omen/Reports`
- **SQL Server Agent** — running, startup type Automatic *(verify this is Automatic and not Manual)*
- **Authentication mode** — mixed mode (SQL Server **and** Windows), enabled after install
- **SQL login** — `ssrs_reader`, member of `db_datareader` on `ScratchTest`
- **Scratch objects** — `ScratchTest` database, `dbo.TestRows` table, `ScratchReport/TestReport` deployed and rendering

---

## Mistakes made, and what they taught

### 1. Downloaded Evaluation edition instead of Developer

**What happened:** Microsoft's download page offers two free options side by side. Evaluation was picked.

**Plain explanation:** Both have the full Enterprise feature set. Developer never expires; Evaluation stops working after 180 days. Nothing functional differs.

**Consequence:** None for a two-day project. If the environment is kept long-term, run an *edition upgrade* through the SQL Server setup wizard's Maintenance section — no reinstall needed.

### 2. Confused the two SSRS URLs

**What happened:** `/ReportServer` and `/Reports` look interchangeable. They are not.

**Plain explanation:**
- `http://omen/ReportServer` is the **web service** — the machine-facing endpoint. Visual Studio deploys *to* this one. It renders as a bare directory listing.
- `http://omen/Reports` is the **web portal** — the human-facing website where reports are browsed and run.

**Rule:** deployment target is always `/ReportServer`. Viewing is always `/Reports`.

### 3. Checked the portal before the report server database existed

**What happened:** `http://omen/Reports` returned 404.

**Plain explanation:** SSRS stores every report, folder, permission, and schedule inside its own database (`ReportServer`). Until that database is created in Reporting Services Configuration Manager, the portal has nothing to serve and returns a 404 — which looks like a broken URL but is actually "not configured yet."

**Diagnostic that saves time:** test `/ReportServer` first. If the web service responds but the portal 404s, the problem is the Web Portal URL step. If neither responds, the problem is the database step.

### 4. Added a dataset before adding the data source to the report

**What happened:** `ScratchDS` did not appear in the Add Dataset dropdown.

**Plain explanation:** A **shared data source** is a connection defined once at the *project* level so several reports can reuse it. But each report also needs its own **reference** pointing at that shared source. Creating it in Solution Explorer makes it available to the project; it does not automatically attach it to any individual report.

**Correct order:** Report Data pane → right-click *Data Sources* → Add Data Source → "Use shared data source reference" → *then* add the dataset.

### 5. Ended up with a duplicate data source (`DataSource1`)

**What happened:** The report had both `ScratchDS` (shared reference) and `DataSource1` (embedded connection).

**Plain explanation:** An **embedded** data source lives inside one report's `.rdl` file and is invisible to other reports. When the Add Dataset dialog can't find a data source to use, it quietly creates an embedded one. So the report was actually reading through `DataSource1`, not the shared source — which is why credentials had to be set on `DataSource1`.

**For the real build:** create **one** shared data source, attach it to all three reports, and configure stored credentials **once**. Three embedded data sources means configuring credentials three times and fixing three places when something changes.

### 6. Credential type did not match the username format

**What happened:** `rsInvalidDataSourceCredentialSetting`, then "Couldn't connect."

**Plain explanation:** Two unrelated things went wrong in sequence.

First, the report server needs **stored credentials**. Previewing inside Visual Studio runs the query as the logged-in user. The report server runs **unattended** — nobody is logged in — so it must have its own saved username and password.

Second, the credential *type* dropdown and the username *format* must agree:
- **Windows user name and password** → `OMEN\sheha`
- **Database user name and password** → a SQL login like `ssrs_reader`

A Windows-format username submitted under "Database user name and password" is sent to SQL Server as a SQL login that doesn't exist, so it fails.

**Resolution:** created the `ssrs_reader` SQL login, enabled mixed-mode authentication, restarted the SQL Server service, and matched the type to the username.

**Note:** mixed-mode authentication is off by default. Enabling it in Server Properties → Security does nothing until the SQL Server service is restarted.

### 7. Assumed Preview meant it worked

**Plain explanation:** The Preview tab in Visual Studio renders the report locally using the current user's identity. It proves the query and layout are valid. It proves **nothing** about whether the report server can deploy, authenticate, or serve the report.

**Rule:** a report is not working until it renders in a browser at `/Reports`.

---

## Carry-forward for the real build

1. **One shared data source**, referenced by all three reports. Configure credentials once.
2. **Stored credentials are mandatory**, not optional — a scheduled subscription runs with nobody logged in, so it cannot prompt.
3. **The `ssrs_reader` pattern is the security model in miniature.** For the real database, instead of `db_datareader` on everything, grant `EXECUTE` on the reporting stored procedures and `SELECT` on approved views, with no direct access to the base tables.
4. **Confirm SQL Server Agent startup type is Automatic**, not just started — otherwise it stops on reboot and the backup/maintenance jobs fail silently.
5. **Scratch objects** (`ScratchTest`, `ScratchReport` folder) can stay or be dropped. They don't interfere.
