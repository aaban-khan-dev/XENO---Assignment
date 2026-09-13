# Findings

What this dataset could and could not verify about the query, plus two questions the data cannot answer.

Backed by `extra_sql/01_fixture_sensitivity.sql`. Run with `python run.py --extra`.

---

## The headline: "reached" and "targeted" are different metrics, and this data cannot tell them apart

The data dictionary describes `target_base` as counting distinct customers **reached**, and talks about a customer who "finally gets delivered" still counting once. That phrasing points at successful deliveries only.

The metric's own name is `target_**base**`, and the brief calls it "qualifying **sends**." Both of those point at everyone targeted, regardless of outcome.

Those are two genuinely different business questions:

- **Reached** excludes a customer you attempted five times and never got through to.
- **Targeted** includes them.

On any real month the two would diverge constantly, because some customers exhaust every retry and are never delivered to.

Here they are identical. Computing the metric with `delivery_status = 900` returns **22**, and computing it across all attempts also returns **22**.

The reason is specific and checkable: **zero customers in this dataset lack a successful delivery.** C2 failed once then succeeded. C3 failed twice then succeeded. D1 failed once then succeeded. Every failure is shadowed by a later success within the same chain, so the two definitions collapse onto the same number.

This is not a defect in the query. It is a definitional question that would need answering before the metric went into production, and I would raise it with Finance rather than pick a reading and move on. If the answer is "reached," a customer who was never successfully contacted should drop out of the count, and on a real month that would change the number.

---

## Four variants, all wrong in production, all returning 22

Landing on the right number does not demonstrate the logic is right. It demonstrates the query is not wrong in any way this dataset can expose.

To test that, I took the correct query and broke it four ways, one condition at a time:

| Variant | What is broken | Result | Distinguishable here? |
|---|---|---|---|
| a | nothing — the correct query | 22 | — |
| b | status list narrowed to `approved` only | 22 | no |
| c | `processing_status` condition dropped entirely | 22 | no |
| d | counts successful deliveries only | 22 | no |
| e | Diwali name filter applied | 22 | no |

All four broken variants pass. The supporting query counts the rows that would have caught each one:

| Condition | Rows exercising it |
|---|---|
| Campaigns with a finalized status other than `approved` | 0 |
| Campaigns not yet processed | 0 |
| Customers never successfully delivered to | 0 |
| Campaigns without "Diwali" in the name | 0 |
| Sends outside the October window | 0 |

Taking them in turn.

**Variant b.** The data dictionary lists four statuses as finalized and reportable: `approved`, `aborted`, `resumed`, `stopped`. Only `approved` appears here. A query written as `creation_status = 'approved'` would silently exclude three categories of legitimate campaign in production, and returns the correct answer on this data.

**Variant c.** The reporting gate has two halves. All seven campaigns are `processed`, so the second half excludes nothing. Dropping it entirely changes no result here.

**Variant e.** The brief scopes to Diwali campaigns, but all seven campaign names match. The filter is a no-op, so including it proves nothing about whether the scoping was done correctly.

**Variant d** is different in kind — it is not a bug but the ambiguity described above.

---

## Two questions this dataset does not pose

**What happens when a retry chain crosses a month boundary?**

`target_base` is reported per period, but a chain is the unit being counted. If a campaign sends on 29 October and its retry sends on 2 November, which month owns that customer? Counting them in both double-counts; counting them in neither loses them; counting at the root's date attributes November activity to October.

Every send here falls between 3 and 20 October, so the question never arises. It would arise on the first real month.

**What happens when an ineligible campaign is a chain root rather than a leaf?**

Campaign 9004 fails the reporting gate, and it happens to be a leaf with nothing after it. Removing it is unambiguous.

Had 9001 been the unapproved one, with approved children 9002 and 9003 beneath it, the correct treatment is genuinely unclear. Do the children form their own chain and get counted? Do they disappear with their root? Do they become standalone campaigns, and therefore get counted by attempts rather than by people — which would change the number again?

I applied the gate inside the chain walk rather than after it, so an ineligible campaign cannot carry its descendants into a chain. That is a defensible reading, but it is a choice rather than a rule the documentation settles.

---

## Two smaller notes

**No data-quality adjustments exist in this reconciliation.** Twelve integrity checks all returned zero. The entire gap between 30 and 22 is definitional. That is unusual enough to be worth stating, since most reconciliations mix cleaning with rule application and this one is purely the latter.

**Timestamps are stored as text, not dates.** Period filtering is therefore string comparison, which is correct only because ISO-8601 sorts lexicographically in chronological order. It breaks on any other format, and the strings carry no timezone offset. `sent_time` and `scheduled_time` are identical in every row here, so the choice between them cannot affect the result — though on production data it would, since a send scheduled in one month can land in the next.