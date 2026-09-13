# Municipal Assessment & Tax Reporting — Project Specification

**Build window:** 2 days (Sep 9–11, 2026). Application submits Sep 12.
**Platform:** Windows. SQL Server Developer Edition, SSMS, SSRS, Report Builder or Visual Studio with the SSRS extension.
**Repo:** GitHub. Scripts are the artifact, not the `.bak`.

---

## 1. Purpose

Build a working SQL Server + SSRS reporting environment against a municipal property assessment and taxation domain. The project exists to produce hands-on evidence in areas not covered by existing professional experience: SSRS report authoring, scheduled report delivery, SQL Server administration and maintenance, backup and restore verification, database-level security, query tuning, and the municipal Land Management / Mass Appraisal domain.

Existing experience already covers SQL Server development (stored procedures, triggers), business applications, requirements gathering, system support, SaaS administration, integrations, access control, documentation, and full-stack development. This project does not need to re-demonstrate those.

**Framing constraint.** This is a simplified reporting model built for SQL Server / SSRS practice. It is not a reconstruction of the City of St. John's real taxation system or business rules. All data is synthetic. The README must state this explicitly. The claim being made is "I built a working SQL Server/SSRS environment covering a relevant domain," never "I know how municipal taxation works."

---

## 2. Data

**All data is synthetic.** Real open data is not viable for this domain:

- The City of St. John's provides a map viewer, not a downloadable open data catalogue.
- The provincial NL open data portal carries population, transportation, health, justice and fiscal datasets — no municipal assessment rolls or parcel-level tax data.
- Assessment records tie parcels to named owners. Publishing real owner records to a public repo is inappropriate regardless of availability.

**Generate defects deliberately** so the ETL step is real work:

- Inconsistent address casing and whitespace
- Nulls in optional fields (unit numbers, secondary owner)
- Duplicate and near-duplicate owner names
- A small number of orphan records that must be caught in transform
- Occasional out-of-range or malformed values (e.g. assessed value of 0, a bad date)

**Load path:** raw generated data → staging table → transform → normalized schema. Do not insert directly into final tables. The transform must handle or reject the defects above, and rejections should be logged, not silently dropped.

**Volume:** enough that indexes matter. Target roughly 50,000 properties, 5 tax years, and payment records at a realistic rate. Small enough to rebuild fast, large enough that a bad query plan is visible.

---

## 3. Schema

Nine tables:

| Table | Purpose |
|---|---|
| `Ward` | Lookup |
| `PropertyClass` | Lookup — residential, commercial, industrial, etc. |
| `Property` | Parcel identifier, address, ward FK, property class FK |
| `Owner` | Owner records |
| `PropertyOwner` | Many-to-many, **effective-dated** (valid from / valid to) |
| `Assessment` | Assessed value by property by tax year |
| `TaxLevy` | Rate by property class by tax year |
| `TaxBill` | Bill issued against a property for a tax year |
| `Payment` | Payments applied against bills |

### Two design decisions that must be implemented

**1. `PropertyOwner` is effective-dated.** A property can change ownership over time, including mid-tax-year. Queries must resolve "who owned this on date X" rather than assuming one current owner. This is the systems-analysis problem worth being able to explain.

**2. `TaxBill` preserves historical values.** The bill stores the assessed value and tax rate *used at the time it was generated*. It must not be recalculated by joining to whatever `TaxLevy` or `Assessment` row exists later. Recalculating historical bills against current rates is the classic defect in this domain and avoiding it is a deliberate, defensible choice.

Reports must require multi-table joins. Anything answerable from a single flat table is not exercising the design.

---

## 4. Database layer

- **Reporting views** for common report bases.
- **Parameterized stored procedures** as report datasets. **No SQL embedded in RDL files.** This mirrors the reporting architecture the posting describes and keeps the SQL independently testable in SSMS.
- **Deliberate indexes**, each with a stated reason recorded in the README. Not "indexed everything."

---

## 5. Reports (three) + one subscription

| # | Report | Demonstrates |
|---|---|---|
| 1 | Assessment totals by ward and property class | Parameters (tax year, class), aggregation, chart |
| 2 | Ward summary → property detail | Drill-through navigation |
| 3 | Accounts in arrears with aging buckets | Business logic, date arithmetic, exception reporting |

The scheduled item is **an SSRS subscription on one of the three reports**, not a fourth report. Configure delivery to a file share, or email if the local SMTP setup permits.

**Arrears logic:** keep it simple and document the assumptions in the README. Aging buckets (e.g. current, 30, 60, 90+), partial payment allocation, and any penalty treatment are *assumptions*, not claims about real municipal billing practice. Do not volunteer detail about real billing rules in an interview.

---

## 6. Security — two layers

**Database layer:** create a reporting role that can `EXECUTE` the reporting stored procedures and `SELECT` from approved views, with **no direct access to the underlying transactional tables**. Least privilege at the data layer.

**Report server layer:** restrict one report or folder in SSRS by role.

Both layers together are the point. Either alone is weaker.

---

## 7. SQL Server administration

Kept deliberately narrow to fit the window:

- One **full backup** job on a schedule
- **At least one test restore** from that backup, to a second database name, with a verification query run against the restored copy
- One **maintenance job** covering index rebuild/reorganize and statistics update

The restore test is the item that matters most. It proves the backup is usable rather than proving you found the backup wizard.

**Explicitly out of scope:** differential backups, retention/cleanup strategy, Query Store. Cut for time. Add only if everything else is complete.

---

## 8. Performance tuning

One exercise, done properly:

1. Identify one reporting query that performs poorly against the initial schema.
2. Capture the **actual execution plan** and `SET STATISTICS IO, TIME ON` output.
3. Make an index or query change **for a defensible reason**.
4. Capture the after state the same way.
5. Record before/after in a small table in the README.

Do not manufacture dramatic numbers. The goal is to show the analysis process, and a modest honest improvement is more credible than a suspicious one.

---

## 9. Build order

Strictly sequential. Do not skip ahead.

```
1.  Environment: SQL Server + SSMS + SSRS installed, report server configured,
    trivial test report deployed and rendering in the browser
2.  Schema (DDL)
3.  Data generation → staging → transform → normalized tables
4.  Reporting views + parameterized stored procedures
5.  Report 1 (parameters, aggregation, chart)
6.  Report 2 (drill-through)
7.  Report 3 (arrears, aging buckets)
8.  Database-level reporting role and permissions
9.  SSRS folder permissions + subscription
10. Backup job + test restore + verification query
11. Maintenance job (index + statistics)
12. Query tuning exercise, before/after captured
13. README, ERD, screenshots
```

**Milestone 1 is a go/no-go gate.** SSRS installs and configures separately from the database engine. Get a trivial report rendering before writing a single line of schema. If milestone 1 is not done early, the project should be reconsidered rather than half-built.

---

## 10. Cut line

Decide this now, not at 11pm on day two.

**Tier 1 — must ship, or the project isn't worth listing:**
steps 1–8 (environment, schema, ETL, procs/views, all three reports, database role)
plus step 10 (backup + verified restore)

**Tier 2 — ship if Tier 1 is done:**
SSRS folder permissions and subscription (9), maintenance job (11), tuning exercise (12)

**Tier 3 — only if everything else is finished:**
Query Store, differential backups, cleanup strategy, ERD polish

If only Tier 1 ships, there is still a legitimate two-bullet resume entry. Chasing Tier 3 while Tier 1 is half-built produces nothing.

---

## 11. Repository structure

```
/database
    schema/          DDL
    staging/         generation + import scripts
    transform/       staging → normalized
    views/
    procedures/
    security/        roles, grants
    jobs/            backup, maintenance (scripted out)
/reports
    *.rdl
/performance
    before/          execution plan, STATISTICS IO/TIME
    after/
    tuning-notes.md
/docs
    erd.png
    screenshots/
README.md
```

---

## 12. README contents

Short. Roughly in this order:

1. Overview — one paragraph, including the explicit "simplified practice model, synthetic data" statement
2. Architecture / ERD
3. Design decisions — effective-dated ownership, historical bill preservation, index choices
4. Assumptions — especially the arrears/aging logic
5. Report screenshots
6. SQL Server administration — backup, restore verification, maintenance
7. Security model — both layers
8. Before/after tuning table

---

## 13. Resume entry (only what actually ships)

Draft, to be trimmed to what is genuinely complete on Sep 12:

> **Municipal Assessment & Tax Reporting** | SQL Server, SSRS, T-SQL
> - Designed a normalized property assessment and tax billing schema with effective-dated ownership and historical bill preservation; loaded synthetic data through a staging layer with transform-time validation, and exposed report datasets through parameterized stored procedures and reporting views.
> - Built parameterized SSRS reports including drill-through and aging-based exception reporting with scheduled subscription delivery; implemented least-privilege access at both the database and report-server layers, and configured backup, verified restore, and index/statistics maintenance jobs with a documented query-tuning exercise.

**Rule: only claim what is finished and in the repo by submission.**
