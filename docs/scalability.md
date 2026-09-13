# Scalability

Assessment of how the reconciliation query behaves at production volume, and what would be required to support it.

Backed by `extra_sql/02_scalability.sql`. Run with `python run.py --extra`.

---

## Scope of this analysis

The reconciliation is correct on the supplied dataset. Correctness at 30 rows does not establish viability at production volume, and three questions remain open.

**Whether performance can be assessed from a 30-row fixture.** Runtime cannot be measured meaningfully at this size. The access path selected by the query planner can be, and it is determined by schema rather than row count. Section 1 sets out why this constitutes evidence rather than estimation.

**Which component degrades at scale.** The recursive chain resolution is the most structurally complex part of the query but is not the limiting factor. Sections 2 and 3 identify the actual constraint, including one cost the database is absorbing silently on every execution.

**Whether indexing is sufficient.** It is not. Section 5 covers the operation that indexing cannot address, which determines whether the query is viable in production. Sections 6 and 7 set out the changes that would be required.

Summary: indexing resolves row access and leaves aggregation unchanged. The structural remedy is to remove chain resolution from the query path.

---

## 1. Method

Every query against this fixture returns instantly, so runtime measurement is not informative at this size.

The **access path** is informative. It is the strategy the planner selects for retrieving rows, and it depends on the available indexes rather than on the number of rows present. A query planned as a full table scan is planned identically at 30 rows and at 50 million; only the execution cost differs.

`EXPLAIN QUERY PLAN` output against this database is therefore direct evidence of behaviour at scale. All plan output quoted below is verbatim.

The analysis creates indexes in order to compare plans before and after. It runs against a temporary copy of `comm_log.db`, which is removed on completion. The supplied database is not modified.

---

## 2. Baseline: no indexes present

Neither table carries an index. In SQLite, `id integer primary key` aliases the internal rowid and defines the table's physical ordering without creating a secondary structure. No index exists on `merchant_id`, `communication_id`, `sent_time`, or `parent_id`.

Every predicate in the reconciliation therefore requires a full table read.

---

## 3. Query plan analysis

### Log-side filter

Merchant and reporting-period predicate, before and after indexing:

```
before   SCAN communication_log

after    SEARCH communication_log USING INDEX idx_log_covering
                (merchant_id=? AND sent_time>? AND sent_time<?)
```

A full table read is replaced by a bounded index seek. At production volume this is the difference between reading the complete send history and reading only rows within the reporting period.

### Recursive chain walk

```
before   SEARCH campaign USING AUTOMATIC PARTIAL COVERING INDEX
                (merchant_id=? AND processing_status=? AND parent_id=?)
         BLOOM FILTER ON campaign (...)

after    SEARCH campaign USING INDEX idx_campaign_parent (parent_id=?)
```

The `AUTOMATIC` designation is significant. It indicates that SQLite found no usable index on `parent_id`, determined that the join would be prohibitively expensive without one, and constructed a transient index at execution time before discarding it. That construction cost is incurred on every execution.

The planner is identifying the missing index directly. Creating `idx_campaign_parent` makes the structure persistent, and the accompanying bloom filter is no longer generated, as it was compensating for the same absence.

### Aggregate effect

The complete reconciliation plan reduces from 13 steps to 12, with three scans replaced by index seeks.

---

## 4. Recommended indexes

```sql
CREATE INDEX idx_log_covering
    ON communication_log (merchant_id, sent_time, communication_id, customer_id);

CREATE INDEX idx_campaign_parent
    ON campaign (parent_id);
```

Column order in `idx_log_covering` is intentional. The leading columns `(merchant_id, sent_time)` match the query predicate and bound the range scan. The trailing columns `(communication_id, customer_id)` supply every value the aggregation requires, allowing the operation to complete without accessing the base table. This is reflected in the `COVERING` designation in the plan output above.

`idx_campaign_parent` supports the recursive join on the campaign graph.

---

## 5. Limitation not addressed by indexing

`USE TEMP B-TREE FOR GROUP BY` is present in both the indexed and non-indexed plans.

The aggregation groups by chain root, which is not a stored column but a value derived by the recursive walk during query execution. No index can support grouping on a value that does not exist until the query runs. SQLite therefore materialises a temporary B-tree, and at sufficient volume this operation exceeds available memory and spills to disk.

This limitation is more consequential than the improvements described above, as it governs whether the query remains viable in production. Indexing alone does not resolve it.

---

## 6. Structural recommendation

The query separates the recursive component from the volume-bearing component by design.

`campaign` grows with marketing activity — a small number of rows added when campaigns are created. `communication_log` grows with send volume — one row per message, indefinitely. These grow at materially different rates, and the recursion operates only on the former.

This separation permits the campaign-to-chain-root mapping to be **materialised as a table**, refreshed on campaign changes rather than derived on each report execution. Three consequences follow.

Chain resolution is removed from the query path entirely, becoming a maintenance process triggered by campaign changes, which are infrequent relative to reporting frequency.

The `GROUP BY` then operates on a stored column rather than a derived value, making the aggregation indexable and removing the temporary B-tree identified in Section 5.

The reporting query reduces to a join between the log table and a small lookup table, a form that partitions and parallelises predictably.

---

## 7. Partitioning

`target_base` is reported per merchant per period. Partitioning `communication_log` on `sent_time` allows a monthly report to prune to a single partition irrespective of the volume of retained history.

Composite partitioning on `(merchant_id, sent_time)` extends this, as merchant appears in every predicate. On a columnar warehouse, the equivalent mechanisms are sort keys or clustering on the same two columns.

---

## 8. Note on the before/after comparison

Introducing `idx_log_covering` alters the order in which rows are returned, as the index yields rows in index order rather than insertion order. The result set is unchanged and the aggregate is unaffected.

The general implication is that an unordered query elsewhere in a codebase may change its output ordering when an index is introduced. An explicit `ORDER BY` should be specified wherever ordering is relied upon.