# Investigation

How 30 became 22, in the order the questions arose.

Finance reports `target_base` for merchant 501's Diwali campaigns in October 2026 as **22**. A plain count of `communication_log` returns **30**. This is the work of explaining the difference.

Each section below has a plain summary and, underneath, the technical detail. Every claim is backed by a file in `sql/` that can be re-run.

---

## 01 — Table inventory

**What it asked.** What is actually in this database, before counting anything?

**What it found.** Two tables: 7 campaigns, and a log of 30 individual send attempts. Most of what mattered here was about how the data is stored rather than what it says.

Three things carried forward.

There are no indexes on either table. Every question asked of this database reads all the data from beginning to end. Fine at 30 rows; the entire problem at scale.

Dates are not stored as dates. They are plain text, `2026-10-03 10:00:00` as a string. Comparisons are character-by-character. That works here, but only because the format happens to sort correctly.

Most importantly: **nothing in the schema forces a log row to point at a campaign that exists.** There is no foreign key. If a message named a campaign that had been deleted, it would silently disappear from any report with no error raised. That makes the orphan check later a real check rather than box-ticking.

<details>
<summary>Technical</summary>

Row counts, `sqlite_master` for DDL, index inventory, and `typeof()` per column grouped by storage type so a mixed-affinity column would surface as two rows rather than hiding behind one summary value.

Zero explicit indexes. `id integer primary key` in SQLite aliases the internal rowid, so it is the table's physical ordering and creates no secondary B-tree. No `FOREIGN KEY` on `communication_log.communication_id`.

`campaign.parent_id` returns two `typeof()` rows — 4 integer, 3 null. That is nullability, not type inconsistency; every other column returns exactly one. The 3 nulls are the first structural signal: three campaigns have no parent.

`sql/01_table_inventory.sql`
</details>

---

## 02 — What varies and what does not

**What it asked.** Which columns carry information, and which say the same thing in every row?

**What it found.** Six columns never change. Every send is SMS, every row belongs to merchant 501, every campaign has finished processing, every send costs one credit.

This matters for a reason that is easy to miss. The brief scopes the work to "all Diwali campaigns," which sounds like an instruction to filter. But **all seven campaigns have "Diwali" in the name.** The filter removes nothing. Writing it or omitting it produces the same answer, which means it cannot demonstrate that the data was scoped correctly.

The same is true of the requirement that a campaign must have finished processing. All seven have. That condition also excludes nothing.

So two of the rules the documentation sets out are untestable against this data. They would matter on a real month. Here they are invisible.

<details>
<summary>Technical</summary>

`COUNT(DISTINCT)` per column, value distributions on the low-cardinality ones, and an explicit test of whether the Diwali predicate discriminates (7 of 7 match).

`creation_status` holds only `approved` (6) and `approval_awaiting` (1), against four finalized values documented in the data dictionary. `delivery_status`: 900 × 26, 1100 × 4. Coverage 3–20 October, zero rows where `sent_time` differs from `scheduled_time`, zero rows outside the window.

The period filter uses a half-open interval, `>= '2026-10-01' AND < '2026-11-01'`. A closed upper bound of `<= '2026-10-31'` silently drops the final day once timestamps carry a time component, because `'2026-10-31 14:00:00' > '2026-10-31'` as a string.

`sql/02_column_cardinality.sql`
</details>

---

## 03 — What does one row mean?

**What it asked.** Is one row one customer, or one attempt?

**What it found.** This is where the problem starts.

One row is **one attempt to send a message**, not one customer. If a send fails and is tried again, that is two rows for one person.

Three customers appear more than once — C2, C3 and D1. In every case the repeats are spread across *different but connected* campaigns, and in every case the earlier attempt had failed. Someone tried, it bounced, they tried again.

A fourth case looks similar and is not. Customer C20 received two messages ten days apart, and **both were delivered successfully**.

That detail settles it. You only retry something that failed. Two successes cannot be retries of one another. So C20 was deliberately messaged twice, as two separate marketing events.

The data establishes this on its own. It did not require taking the documentation's word for it.

<details>
<summary>Technical</summary>

`id` is unique, 30 distinct against 30 rows. `(communication_id, customer_id)` yields 29 distinct pairs against 30 rows — one excess.

The excess is C20 under campaign 9101: `distinct_outcomes = 1` (both 900), sends ten days apart, on a campaign with null `parent_id` and no children.

Cross-campaign repeats — C3 across 9001/9002/9003, C2 across 9001/9002, D1 across 9201/9202 — all follow a 1100.

Empirical signature separating the two patterns:
- repeat **across** `parent_id`-linked campaigns, following a failure → retry
- repeat **within** one unlinked campaign, following a success → re-target

Per-campaign gap between attempts and distinct customers is 0 everywhere except 9101. So duplication is entirely a cross-campaign phenomenon, which means the correct grouping key is not a column in either table. It has to be derived from the graph. That forces the next step.

`sql/03_grain_analysis.sql`
</details>

---

## 04 — How campaigns connect

**What it asked.** What shape is the retry structure?

**What it found.** When a marketer re-sends to people who did not receive the message, the system does not add rows to the original campaign. It creates a **new campaign** pointing back at the old one.

So what a person would call "our Diwali campaign" can exist in the database as four separate campaign records, with one customer appearing under three different campaign IDs.

Mapping those connections gives three families:

- One family of four campaigns, chained **three deep**, and it branches — the original has two separate follow-ups rather than one.
- One campaign standing entirely alone.
- One family of two.

The three-deep chain is the trap. The instinctive way to link a campaign to its follow-up handles exactly **one** hop. It would work correctly on the two-campaign family and quietly get the three-deep family wrong. No error, just a plausible wrong number.

<details>
<summary>Technical</summary>

`WITH RECURSIVE` resolving every campaign to its root with depth and path.

Roots: 9001 (chain size 4, max depth 3, branching factor 2 at the root), 9101 (standalone), 9201 (size 2).

Graph integrity clean: no `parent_id` pointing at a missing campaign, nothing unreachable from a root, no cycles. The recursion carries `WHERE depth < 100` as a cycle guard, since `parent_id` has no constraint preventing one.

**A bug worth recording.** The first version of the node classifier misreported 9101 as a chain root rather than standalone. A `LEFT JOIN` produces `NULL`, not `0`, for a campaign with no children, so the `child_count = 0` condition never matched. It was caught because a second query derived chain size from the recursion instead of the join, and the two disagreed. Fixed with `COALESCE`. Computing the same quantity two ways is what surfaced it.

`sql/04_campaign_graph.sql`
</details>

---

## 05 — Which campaigns count

**What it asked.** Which campaigns are eligible for official reporting, and what do the ineligible ones carry?

**What it found.** A campaign counts only once two independent things have happened: it has been approved, and the send pipeline has finished.

Those run separately, and that creates a gap. **One campaign had its messages sent before anyone approved it.** Four real messages to four real customers, all four delivered successfully. On paper the campaign was never signed off, so Finance does not count it.

The uncomfortable part: those four rows look entirely normal. Nothing about them is flagged, failed, or unusual. Their ineligibility is invisible from the message log — only the campaign record reveals it.

That is the first adjustment. 30 becomes 26.

<details>
<summary>Technical</summary>

Status cross-tab with log volume attached. Campaign 9004: `approval_awaiting` + `processed`, 4 rows, 4 distinct customers, all delivered. Note it **is** processed — a filter on `processing_status` alone retains it.

Established here as well: three different queries return identical results on this data. The correct four-value status set, a version omitting the processing condition, and a too-narrow `creation_status = 'approved'`. Only the first is right in production. Quantified further in `docs/findings.md`.

9004 is a **leaf** with no children, so dropping it is clean. Had the ineligible campaign been a chain *root* with eligible children, the correct treatment would be genuinely ambiguous. This dataset does not pose that question.

`sql/05_eligibility_gate.sql`
</details>

---

## 06 — What could be broken, and is not

**What it asked.** Which data-quality problems would change the number, and are any of them present?

**What it found.** Twelve checks: messages pointing at campaigns that do not exist, the same customer written two slightly different ways, timestamps that do not make sense, dates outside the reporting month, undocumented delivery outcomes.

All twelve came back clean.

That is worth stating rather than skipping, because it establishes what kind of reconciliation this is. **The gap between 30 and 22 has nothing to do with messy data.** Every step is a business rule about what Finance means by a qualifying send. Nothing is a typo or a corrupt record.

<details>
<summary>Technical</summary>

Orphan log rows; merchant mismatch between log and campaign; cross-merchant `parent_id`; leading or trailing whitespace in `customer_id`; case or whitespace variants across distinct ids; empty ids; unparseable `sent_time`; rows outside the period; `sent_time` earlier than `scheduled_time`; the two timestamps falling in different months; `delivery_status` outside {900, 1100}; campaigns with no log rows. All zero.

Each was genuinely possible: no foreign key, free-text `customer_id`, nothing constraining `merchant_id` to agree across tables, no cycle constraint on `parent_id`.

`sql/06_integrity_checks.sql`
</details>

---

## 07 — Why the obvious answers fail

**What it asked.** Can any filter get from a naive count to 22?

**What it found.** Two natural ways to count, after excluding the unapproved campaign:

Every message sent: **26.** Different people messaged: **21.**

Finance says 22, which sits between them.

That is what cracks the problem open. Filtering only ever removes things — it moves a count down, never up. **There is no filter that turns 21 into 22.**

So the problem is not which rows are included. The problem is which *unit* is being counted.

Looking family by family, the arithmetic then points at the answer by itself. There are five repeated sends in total. Collapse all five and the result is 21, one short. Collapse only the ones inside connected families, leaving the standalone campaign alone, and the result is exactly 22.

The rule was not taken on faith from the documentation. **The number reconciles one way only.**

<details>
<summary>Technical</summary>

Baselines: 30 all attempts, 25 all distinct customers, 26 eligible attempts, 21 eligible distinct customers.

Per-chain breakdown: repeats of 3 (root 9001), 1 (9101), 1 (9201). 26 − 3 − 1 = 22. Collapsing 9101 as well gives 21.

Data and documentation agree independently, which is a stronger position than either alone.

`sql/07_naive_baseline.sql`
</details>

---

## 08 — Building the mapping

**What it asked.** For every campaign that counts, which family does it belong to, and is that family chained or standalone?

**What it found.** Two design decisions here are worth explaining.

The ineligible campaign is removed **while** tracing connections, not afterwards. It makes no difference on this data, because that campaign happens to sit at the end of a branch with nothing after it. But if an ineligible campaign sat in the *middle* of a chain, filtering afterwards would leave its follow-ups attached to a family they no longer legitimately descend from.

And every campaign was verified to have found a home. If one had been stranded — unreachable from any starting point — its messages would have vanished from the total with no error at all. Six eligible campaigns, six resolved, none lost.

Separately: the family connections are traced **independently of the message log**. Campaign records grow slowly, as marketers create campaigns. The log grows with every message ever sent. Keeping those apart is what allows this to survive on production data.

<details>
<summary>Technical</summary>

Eligibility applied inside the recursive CTE rather than after the walk.

Completeness assertion: 6 eligible, 6 resolved, 0 unresolved. The recursion seeds from `parent_id IS NULL`, so an eligible campaign whose parent was gate-excluded would be unreachable and dropped silently.

Chain 9001 is size 3 here rather than 4, since 9004 was filtered inside the walk.

The separation of graph walk from fact join is also the basis for the materialised-mapping argument in `docs/scale.md`.

`sql/08_chain_resolution.sql`
</details>

---

## 09 — The answer

**What it asked.** What does the metric actually equal?

**What it found.** Combining the mapping with the message log, and applying a different rule per family:

**Connected families** — count *people*. A customer reached on the third attempt was reached once.
**Standalone campaign** — count *messages*. There are no retries, so every send is its own event.

| Family | Type | Messages | People | Counts as |
|---|---|---|---|---|
| Cart Recovery | chained | 13 | 10 | **10** |
| Flash Sale | standalone | 7 | 6 | **7** |
| Wave 2 | chained | 6 | 5 | **5** |
| | | 26 | 21 | **22** |

The Flash Sale row is the only one taking the messages column rather than the people column. That single row is the entire puzzle.

Both wrong answers, 26 and 21, appear in the same table as the right one. The metric genuinely is two kinds of counting added together, which is why no single aggregate could ever produce it.

<details>
<summary>Technical</summary>

Parameterised on merchant and a half-open period window through a `scope` CTE.

`CASE WHEN campaigns_in_chain > 1 THEN COUNT(DISTINCT customer_id) ELSE COUNT(*) END` per root.

Period and communication-type filters applied at the log join, keeping the graph walk independent of send volume.

SQLite note: `ORDER BY` after a compound `UNION ALL` accepts only a column name or ordinal position, not an expression. An explicit `sort_key` column was needed.

`sql/09_target_base.sql`
</details>

---

## 11 — The bridge

**What it asked.** What is the step-by-step path from the obvious number to the correct one?

**What it found.**

| Step | What | Result |
|---|---|---|
| 0 | Every message in the log | 30 |
| 1 | Remove the campaign that was never approved | 26 |
| 2 | Merge retries in the Cart Recovery family | 23 |
| 3 | Merge retries in the Wave 2 family | 22 |
| final | Leave the Flash Sale campaign alone | **22** |

The last line is the one worth pausing on. It is not a step taken — it is a step **deliberately not taken**, with the reason on the row. That customer's two messages both succeeded, ten days apart, under a campaign with no retries attached. Nothing failed, so nothing was retried.

Every number in the table is calculated from the data rather than typed in.

<details>
<summary>Technical</summary>

Steps derive from the per-root `repeats` column rather than hardcoded literals, so the bridge reconciles against whatever is in the database rather than asserting a remembered result.

`sql/11_bridge.sql`
</details>

---

## What this did not settle

Two things this dataset cannot answer, covered in [findings](findings.md):

The metric's documentation says customers **reached**; its name and the brief say **targeted**. Those are different questions, and this data cannot distinguish them because every customer here eventually received a successful delivery.

And several conditions the documentation requires are never exercised by any row, so a query omitting them returns the correct answer anyway.