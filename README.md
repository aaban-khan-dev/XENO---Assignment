# Comm-Log Reconciliation — Merchant 501, October 2026

> ## Finance target: `target_base = 22`

**Scope:** Merchant `501` · October 2026 · Diwali campaigns

---

## Contents

| Section | What it covers |
|:---|:---|
| [1. The problem](#1-the-problem) | Scope, starting point, and source of the gap |
| [2. Reconciliation bridge](#2-reconciliation-bridge) | Step-by-step reconciliation from 30 to 22 |
| [3. Running the queries](#3-running-the-queries) | How to reproduce the analysis and final result |
| [4. Why no single count reaches 22](#4-why-no-single-count-reaches-22) | The mixed-grain counting rule behind the result |
| [5. Repository layout](#5-repository-layout) | Structure of the project |
| [6. Documentation & additional analysis](#6-documentation--additional-analysis) | Required investigation write-up and additional analysis |
| [7. Use of AI](#7-use-of-ai) | How AI was used and how the results were validated |

---

# 1. The Problem

Finance reports a `target_base` of **22** for merchant `501` across its Diwali campaigns in October 2026.

A straightforward count of `communication_log` returns **30**.

The investigation found no underlying data-quality issue: all twelve integrity checks returned zero. The difference comes from the **reporting rules and counting grain**, rather than malformed or inconsistent records.

### Result at a glance

```text
30  raw send attempts
 ↓
26  after the reporting gate
 ↓
23  after resolving retry chain 9001 → 9002 → 9003
 ↓
22  after resolving retry chain 9201 → 9202
```

> **Final result: `target_base = 22`**

---

# 2. Reconciliation Bridge

| Step | Description | Result | Change | Reason |
|:---:|---|---:|---:|---|
| **0** | Every row in `communication_log` | **30** | — | Starting point: one row represents one send attempt |
| **1** | Exclude campaigns that fail the reporting gate | **26** | **−4** | Campaign `9004` is `approval_awaiting`, so it is not reportable |
| **2** | Collapse retries within `9001 → 9002 → 9003` | **23** | **−3** | `C2` and `C3` were re-attempted through the same retry chain |
| **3** | Collapse retries within `9201 → 9202` | **22** | **−1** | `D1` was re-attempted through the same retry chain |
| **Final** | Keep `9101` uncollapsed as a standalone campaign | **22** | **0** | `C20` was delivered twice with no retry relationship, so both sends remain separate events |

The final row is not an adjustment. It represents the business rule that prevents an additional, incorrect deduplication.

**All values in the bridge are calculated from the database at runtime; none are hardcoded.** The complete reconciliation is reproduced by `sql/11_bridge.sql`.

---

# 3. Running the Queries

**Requirement:** Python 3. No additional packages are required.

```bash
git clone https://github.com/aaban-khan-dev/XENO---Assignment.git
cd XENO---Assignment
```

### Full investigation

```bash
python run.py --trail
```

Runs the complete investigation in sequence, from initial table profiling through the final reconciliation bridge.

This is the recommended command for reviewing **how the result was derived**.

### Final result only

```bash
python run.py
```

Runs the bridge and final reconciliation and prints the resulting `target_base`.

### Run an individual SQL file

```bash
python run.py sql/09_target_base.sql
```

Any file under `sql/` or `extra_sql/` can be executed individually.

`sql/09_target_base.sql` contains the final reconciliation query. The query uses a `scope` CTE for the merchant and reporting period, so the logic is not hardcoded to a single merchant or time window.

### Additional analysis

```bash
python run.py --extra
```

Runs the optional analysis described in [Section 6](#6-documentation--additional-analysis).

### Database safety

The supplied database is **not modified**.

The core reconciliation opens the database in read-only mode. The scalability analysis temporarily creates indexes to compare query plans, but runs against a copy of the database and removes the copy afterwards.

---

# 4. Why No Single Count Reaches 22

After applying the reporting gate, the two obvious counts are:

| Query | Result |
|---|---:|
| `COUNT(*)` — all qualifying send attempts | **26** |
| `COUNT(DISTINCT customer_id)` — all qualifying customers | **21** |
| **Finance target** | **22** |

Neither produces Finance's **22**.

A filter can only remove rows, so it cannot move **21 up to 22**. This rules out filtering as the explanation for the remaining difference.

The underlying issue is the **counting grain**.

`target_base` treats retry chains and standalone campaigns differently:

| Chain root | Type | Attempts | Distinct customers | Qualifying |
|:---:|:---:|---:|---:|---:|
| `9001` | Chained | 13 | 10 | **10** |
| `9101` | Standalone | 7 | 6 | **7** |
| `9201` | Chained | 6 | 5 | **5** |
| **Total** | | **26** | **21** | **22** |

### Counting rule

**Retry chain**

Multiple attempts to the same customer represent the same underlying communication.

```text
A → B → C
```

The customer is counted **once** across the chain.

**Standalone campaign**

Each send is a separate event, even when the same customer appears more than once.

Campaign `9101` is therefore the key edge case. It contributes **7 attempts**, rather than its **6 distinct customers**.

### Final calculation

```text
Retry chain 9001       → 10
Standalone campaign    →  7
Retry chain 9201       →  5
                         ──
                         22
```

This is why:

```text
COUNT(*)                  → 26
COUNT(DISTINCT customer)  → 21
Correct mixed-grain count → 22
```

---

# 5. Repository Layout

```text
data/        supplied files, unmodified
sql/         reconciliation queries, one numbered file per step
extra_sql/   additional analysis beyond the assignment brief
docs/        investigation, findings, and supporting analysis
run.py       execution entry point
```

| Location | Purpose |
|:---|:---|
| `data/` | Supplied database and CSV files |
| `sql/` | Core investigation and reconciliation |
| `extra_sql/` | Additional analysis beyond the required submission |
| `docs/` | Detailed reasoning, findings, and supporting analysis |
| `run.py` | Common entry point for running the SQL workflow |

---

# 6. Documentation & Additional Analysis

## Required Investigation

**[Investigation write-up →](docs/investigation.md)**

This is the detailed write-up of the **required reconciliation work**. It covers `sql/01` through `sql/11` in the same order as the investigation.

For each phase, it documents:

- what was checked
- what the result established
- how the result informed the next step

This directly supports the assignment's evaluation criterion: showing **what was investigated, what did not match, what was checked next, and why**.

The document ends with a short pointer to the open questions explored further in the findings.

---

## Additional Analysis

**[Findings →](docs/findings.md)**

This contains the analysis beyond the core reconciliation, including:

- reached-versus-targeted interpretation
- four deliberately incorrect query variants that also return `22`
- conditions that are not exercised by the fixture
- scalability and query-plan analysis
- the month-boundary retry-chain question
- the ineligible-root question

The fixture-sensitivity and scalability analysis are backed by the corresponding SQL in `extra_sql/`. The remaining points are reasoning about scenarios that are not represented in the supplied data.

---

# 7. Use of AI

AI was used as a development aid, primarily to pressure-test the reasoning and draft SQL that was subsequently validated against the database.

### AI-assisted work

- Initial drafts of profiling and investigation queries
- Recursive CTE structure for retry-chain resolution

### Independent validation

- Every reported number was verified against the supplied database.
- The SQL required to reproduce each result is included in the repository.

### An error caught during validation

The first campaign node-classification query incorrectly classified campaign `9101` as a chain root rather than a standalone campaign.

The issue was caused by a `LEFT JOIN`: campaigns without child rows produce `NULL`, not `0`, so the original `child_count = 0` condition did not identify `9101` correctly.

A second calculation based on the recursive chain mapping produced a conflicting result, which exposed the issue. The query was corrected using `COALESCE`.

This provided an additional validation check: for a metric where the counting grain matters, deriving the same structural property through independent queries helps catch implementation errors.

---

## Final Result

> ### `target_base = 22`

| Metric | Value |
|:---|---:|
| Raw send attempts | 30 |
| Eligible send attempts | 26 |
| Distinct eligible customers | 21 |
| **Final `target_base`** | **22** |

**Core insight:** the correct result requires resolving the **campaign retry graph first**, then applying the appropriate counting grain to each campaign family.
