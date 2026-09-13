# Comm-Log Reconciliation — merchant 501, October 2026

**target_base = 22**

```
git clone https://github.com/aaban-khan-dev/XENO---Assignment.git
cd XENO---Assignment
python run.py
```

Requires Python 3 only. No packages to install.

---

## 1. Reconciliation bridge

| Step | Description | Result | Change | Reason |
|------|-------------|--------|--------|--------|
| 0 | Every row in `communication_log` | 30 | — | Starting point: one row per send attempt |
| 1 | Exclude campaigns that failed the reporting gate | 26 | −4 | 9004 is `approval_awaiting`, so not signed off and not reportable |
| 2 | Collapse retries within chain 9001 → 9002 → 9003 | 23 | −3 | C2 and C3 re-attempted after failure, same underlying communication |
| 3 | Collapse retries within chain 9201 → 9202 | 22 | −1 | D1 re-attempted after failure |
| final | Leave 9101 uncollapsed (standalone, no retry chain) | **22** | 0 | C20 delivered twice 10 days apart with no failure, so not a retry |

The final row is not an adjustment. It is the adjustment deliberately **not** made, and it is where the metric's definition actually lives.

Every value above is computed from the database at run time, not hardcoded. To reproduce the table yourself:

```
python run.py
```

---

## 2. Why no single count reaches 22

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

The arithmetic forces this independently of the documentation. There are five repeated sends in total. Collapsing all five gives 21, one short. Collapsing only the two chained roots gives 22. The number reconciles one way only.

---

## 3. The SQL

`sql/09_target_base.sql` computes the final number. It is parameterised on merchant and period through a `scope` CTE, so it runs for any merchant and any window rather than being hardcoded to this one.

```
python run.py sql/09_target_base.sql
```

`sql/11_bridge.sql` produces the bridge table in section 1.

---

## 4. Running it

| Command | What it does |
|---|---|
| `python run.py` | The answer: bridge table and final number |
| `python run.py --trail` | The full investigation, phases 1–11, in order |
| `python run.py --extra` | Additional analysis (optional, see section 6) |
| `python run.py sql/04_campaign_graph.sql` | Any single file |

`--trail` is the one to run to see how the number was arrived at rather than just what it is. It prints every profiling and reconciliation query in sequence, from the first table inventory through to the bridge.

**The supplied database is never modified.** Phases 1–11 open it read-only, so SQLite refuses any write. The `--extra` analysis creates indexes to compare query plans, so it runs against a temporary copy that is deleted afterwards.

---

## 5. Repository layout

```
data/        supplied files, unmodified
sql/         the reconciliation, one numbered file per step
extra_sql/   additional analysis beyond the brief
docs/        investigation write-up, findings, scalability
run.py       runs any of the above
```

---

## 6. Additional work

Three things beyond what was asked. Each is self-contained — skip freely.

**[Investigation write-up](docs/investigation.md)** — the full reasoning, file by file. What each query asked, what it returned, and why that determined the next step. Written in two layers: plain summary first, SQL detail below. This is the long-form version of how the number was reached.

**[Findings](docs/findings.md)** — what this dataset could and could not verify about the query. Four deliberately broken variants of the correct query all return 22, because the conditions that would separate them never occur in the data. One of those variants is not a bug but a genuine ambiguity in the metric's definition, and it is the most interesting thing here.

**[Scalability](docs/scale.md)** — query plans before and after indexing, using real `EXPLAIN QUERY PLAN` output. Includes what the planner reveals about a missing index, and one limitation that indexing does not fix.

---

## 7. Use of AI

I used Claude throughout, mainly to pressure-test reasoning and to draft SQL I then verified against the data.

What I delegated: initial drafts of the profiling queries, and the recursive CTE structure.

What I verified independently: every number in this repository. Each claim is backed by a query in `sql/` or `extra_sql/` that can be re-run.

Where it was wrong: my first node-classification query misreported campaign 9101 as a chain root rather than standalone. A `LEFT JOIN` yields `NULL`, not `0`, for a campaign with no children, so the `child_count = 0` condition never matched. It was caught because a second query derived chain size from the recursion instead of the join and the two disagreed. The fix was a `COALESCE`, and the lesson was to compute the same quantity two ways when the answer matters.