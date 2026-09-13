# Query Tuning Exercise

## 1. Identifying the target

Measured `SET STATISTICS TIME, IO ON` across all four reporting stored procedures (each called with a realistic parameter) before touching anything:

| Procedure | CPU time | Elapsed time |
|---|---|---|
| `rpt_AssessmentTotalsByWardClass` | 328 ms | 393 ms |
| `rpt_WardSummary` | 532 ms | 267 ms |
| `rpt_PropertyDetailByWard` | 2,063 ms | 1,828 ms |
| **`rpt_ArrearsAging`** | **5,547 ms** | **3,847 ms** |

`rpt_ArrearsAging` was the clear worst performer — over 4x slower than the second-worst, and it's the one report with no parameter that narrows the row set before doing real work (it evaluates all 237,816 tax bills every time).

## 2. Before: execution plan and STATISTICS IO/TIME

Captured in `performance/before/execution_plan.xml` and `performance/before/statistics_io_time.txt`.

The telling line from `STATISTICS IO`:

```
Table 'Worktable'. Scan count 237816, logical reads 1202754, ...
```

`rpt_ArrearsAging` runs on top of `vw_TaxBillPaymentStatus`, which computes each bill's total payments with:

```sql
OUTER APPLY (
    SELECT TotalPaid = SUM(pm.PaymentAmount) FROM Payment pm WHERE pm.TaxBillID = tb.TaxBillID
) pay
```

`Payment` had no index on `TaxBillID` — only its own primary key on `PaymentID`. With 237,816 tax bills and no seek path into `Payment`, SQL Server spooled a worktable and re-scanned it once per bill: 237,816 scans, 1,202,754 logical reads, 3.85 seconds elapsed.

## 3. The change, and why

```sql
CREATE NONCLUSTERED INDEX IX_Payment_TaxBillID
    ON Payment (TaxBillID)
    INCLUDE (PaymentAmount);
```

`TaxBillID` is the lookup key, so it's the index key. `PaymentAmount` is included (not keyed) because it's the only other column the aggregation actually touches — this makes the index **covering** for this specific query: SQL Server can seek directly to a bill's payment rows and sum them from the index itself, without a further lookup into the base table.

This is a targeted, single-purpose index added for a measured reason, not a "index everything" change — the schema otherwise relies on nothing beyond the primary key/unique constraints created with the tables (see `database/schema/02_create_tables.sql`).

## 4. After: execution plan and STATISTICS IO/TIME

Captured in `performance/after/execution_plan.xml` and `performance/after/statistics_io_time.txt`.

```
Table 'Payment'. Scan count 237816, logical reads 759495, ...
```

The `Worktable` spool is gone entirely. `Payment` is still accessed once per bill (237,816 times — that's inherent to the report needing a per-bill total, not something an index removes), but each access is now a direct index seek instead of a scan-and-spool, at roughly 3.2 logical reads per lookup.

## 5. Before / after

| Metric | Before | After | Change |
|---|---|---|---|
| Elapsed time | 3,847 ms | 1,935 ms | ~50% faster |
| CPU time | 5,547 ms | 4,171 ms | ~25% less |
| Logical reads (Payment/Worktable path) | 1,202,754 | 759,495 | ~37% fewer |

This is a modest, honest improvement, not a manufactured one — the report still touches every unpaid bill and every payment, because that's what an aging report inherently has to do. What changed is *how* it gets there: a seek instead of a scan-and-spool.

## 6. Confirming it with Query Store (Tier 3)

Everything above was captured manually (`SET STATISTICS IO, TIME ON`, a captured execution plan). SQL Server's Query Store does this automatically, for every significant query, all the time — worth demonstrating separately since it's a distinct skill from manual tuning.

Enabled Query Store (`database/schema/04_enable_query_store.sql`), then reproduced the same before/after scenario under it (`performance/query-store-demo.sql`): dropped `IX_Payment_TaxBillID`, ran `rpt_ArrearsAging`, restored the index, ran it again. The SQL text never changed — only the index did — so Query Store correctly recorded this as **one `query_id` with two different `plan_id`s**:

| | `plan_id` | Avg duration | Avg logical reads |
|---|---|---|---|
| Before (no index) | 1 | 3,152 ms | 1,208,620 |
| After (with index) | 3 | 1,797 ms | 792,251 |

Consistent with the manually-measured numbers above (same query, same change, two different measurement methods agreeing). The practical value of Query Store over the manual approach: this history is captured automatically for every query going forward, not just the one time someone happens to run `SET STATISTICS ON` around it — useful for catching a plan regression weeks after a change, not just proving one at the moment it's made.
