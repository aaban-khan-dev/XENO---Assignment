# Comm-Log Reconciliation — merchant 501, October 2026

**target_base = 22**

---

## Contents

| Section | What it covers |
|---|---|
| [1. The problem](#1-the-problem) | What was asked and what the gap is |
| [2. Reconciliation bridge](#2-reconciliation-bridge) | Step-by-step from 30 to 22 |
| [3. Running the queries](#3-running-the-queries) | Every command, starting with the full run |
| [4. Why no single count reaches 22](#4-why-no-single-count-reaches-22) | The mixed-grain problem, and the two wrong answers |
| [5. Repository layout](#5-repository-layout) | Where everything lives |
| [6. Additional work](#6-additional-work) | Investigation write-up, findings, scalability — optional |
| [7. Use of AI](#7-use-of-ai) | What was delegated, what was verified, where it was wrong |

---

## 1. The problem

Finance reports `target_base` for merchant 501's Diwali campaigns in October 2026 as **22**. A plain count of `communication_log` returns **30**.

The gap is entirely definitional. Twelve data-quality checks all returned zero, so nothing here is a typo or a broken record. Every step below is a business rule about what counts as a qualifying send.

---

## 2. Reconciliation bridge

| Step | Description | Result | Change | Reason |
|------|-------------|--------|--------|--------|
| 0 | Every row in `communication_log` | 30 | — | Starting point: one row per send attempt |
| 1 | Exclude campaigns that failed the reporting gate | 26 | −4 | 9004 is `approval_awaiting`, so not signed off and not reportable |
| 2 | Collapse retries within chain 9001 → 9002 → 9003 | 23 | −3 | C2 and C3 re-attempted after failure, same underlying communication |
| 3 | Collapse retries within chain 9201 → 9202 | 22 | −1 | D1 re-attempted after failure |
| final | Leave 9101 uncollapsed (standalone, no retry chain) | **22** | 0 | C20 delivered twice 10 days apart with no failure, so not a retry |

The final row is not an adjustment. It is the adjustment deliberately **not** made, and it is where the metric's definition actually lives.

**Every value in this table is computed from the database at run time, not hardcoded.** `sql/11_bridge.sql` reproduces it, and section 3 gives the commands.

---

## 3. Running the queries

Python 3 only. Nothing to install.

```
git clone https://github.com/aaban-khan-dev/XENO---Assignment.git
cd XENO---Assignment
```

### Everything, in order

```
python run.py --trail
```

Runs the full reconciliation from the first table inventory through to the bridge — every profiling query, every check, every intermediate result, in the order the questions arose. This is the one to run to see how the number was reached rather than just what it is.

### Just the answer

```
python run.py
```

Prints the bridge table and the final number. Nothing else.

### A single file

```
python run.py sql/09_target_base.sql
```

Any file in `sql/` or `extra_sql/`. `sql/09_target_base.sql` is the query that computes the final number — parameterised on merchant and period through a `scope` CTE, so it runs for any merchant and any window rather than being hardcoded to this one.

### Additional analysis

```
python run.py --extra
```

Optional. Covered in section 6.

### On the supplied database

It is never modified. The reconciliation opens it read-only, so SQLite refuses any write. The `--extra` analysis creates indexes to compare query plans, so it runs against a temporary copy that is deleted afterwards.

---

## 4. Why no single count reaches 22

After applying the reporting gate, the two obvious queries give:

- `COUNT(*)` — every send attempt: **26**
- `COUNT(DISTINCT customer_id)` — every person: **21**

22 sits between them. A `WHERE` clause only ever removes rows, so it moves a count down, never up. **21 cannot be filtered up to 22.** That rules out every filtering approach at once, without having to enumerate them.

The reason is that `target_base` has a mixed grain. It counts *people* inside retry chains and *attempts* under standalone campaigns:

| Chain root | Type | Attempts | Distinct customers | Qualifying |
|---|---|---|---|---|
| 9001 | chained | 13 | 10 | 10 |
| 9101 | standalone | 7 | 6 | **7** |
| 9201 | chained | 6 | 5 | 5 |
| **Total** | | 26 | 21 | **22** |

9101 is the only root taking the attempts column. That single row is the whole problem.

The arithmetic forces this independently of the documentation. There are five repeated sends in total. Collapsing all five gives 21, one short. Collapsing only the two chained
