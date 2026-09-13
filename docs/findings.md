# Findings

Additional findings from testing the reconciliation against alternative query definitions and checking which documented rules are actually exercised by the dataset.

Backed by `extra_sql/01_fixture_sensitivity.sql`. Run with `python run.py --extra`.

---

## Why this analysis

The reconciliation produces **22**, and the bridge explains how. That answers the primary question.

It also raises three further questions:

**Does producing 22 actually demonstrate that the logic is correct?**  
A query can return the right number because its logic is correct, or because the dataset contains no case capable of exposing a flaw. Those two situations look identical from the final result alone. Section 2 tests this by deliberately changing one condition at a time and checking which incorrect variants the dataset can detect.

**Is the metric itself unambiguously defined?**  
The data dictionary and the brief describe `target_base` in ways that can point to two different metrics. Section 1 examines the distinction between **reached** and **targeted**, and shows why both happen to return 22 on this dataset.

**What could this logic encounter in production that is not represented here?**  
Section 3 covers two situations absent from the fixture where the available documentation does not establish a definitive treatment.

Section 4 records two additional implementation observations that do not affect the current result but could matter on production data.

The short version: **22 is necessary, but not sufficient.** The analysis below documents what the dataset actually verifies, what it cannot distinguish, and which questions should be clarified before production use.

---

## 1. Reached vs. targeted: a business definition that remains unresolved

The data dictionary defines `target_base` as distinct customers **reached**, and specifically describes a customer who "finally gets delivered" as counting once. This suggests that successful delivery is part of the metric definition.

However, the metric name `target_base` and the brief's reference to "qualifying sends" could also be interpreted as counting everyone targeted, regardless of delivery outcome.

These definitions produce different results in production:

- **Reached:** excludes customers for whom every attempt failed.
- **Targeted:** includes those customers because they were still part of a qualifying send.

The current dataset cannot distinguish between the two. Both definitions return **22**.

The reason is specific to this fixture: every customer with a failed attempt eventually has a successful delivery within the same retry chain. C2 fails once before succeeding, C3 fails twice before succeeding, and D1 fails once before succeeding. There are therefore **zero customers who were never successfully delivered to**.

This is not a query issue; it is a business-definition issue. I would confirm the intended interpretation with Finance before treating the metric as production-ready. If `target_base` means **reached**, customers who never receive a successful delivery should be excluded, and the two definitions would diverge on real data.

---

## 2. Passing the expected number is not enough

A query returning **22** does not, by itself, establish that the logic is correct. The dataset must also contain cases capable of exposing incorrect logic.

I tested the correct query by changing one condition at a time. Several deliberately incorrect variants still return 22:

| Variant | Change | Result | Distinguishable on this dataset? |
|---|---|---:|---|
| a | Correct query | 22 | — |
| b | Restrict status to `approved` only | 22 | No |
| c | Remove the `processing_status` condition | 22 | No |
| d | Count successful deliveries only | 22 | No |
| e | Add the Diwali campaign-name filter | 22 | No |

The supporting checks show why these variants cannot be distinguished:

| Condition | Rows exercising the condition |
|---|---:|
| Finalized campaign status other than `approved` | 0 |
| Campaigns not yet processed | 0 |
| Customers never successfully delivered to | 0 |
| Campaigns without "Diwali" in the name | 0 |
| Sends outside the October window | 0 |

### What this means

**Status filtering.**  
The documented finalized and reportable statuses are `approved`, `aborted`, `resumed`, and `stopped`. Only `approved` appears in this fixture. A query restricted to `approved` would therefore produce the correct result here while incorrectly excluding other valid statuses in production.

**Processing status.**  
The reporting rule requires campaigns to be `processed`. All seven campaigns already satisfy this condition, so removing the filter has no effect on this dataset.

**Diwali scoping.**  
All seven campaign names contain "Diwali". The campaign-name filter is therefore a no-op here and does not demonstrate that the scope is being applied correctly.

**Delivery status.**  
This is the `reached` vs. `targeted` ambiguity described above rather than a straightforward query bug. Both definitions happen to produce the same result because every failed attempt is followed by a successful delivery.

The broader point is important: **22 is necessary, but not sufficient evidence that the reconciliation logic is correct.**

---

## 3. Two business questions the dataset does not answer

### 3.1 What happens when a retry chain crosses a month boundary?

`target_base` is reported by period, while the retry chain is the unit being reconciled. If a campaign sends on 29 October and its retry sends on 2 November, the available documentation does not establish which month should own that customer.

Possible treatments have different consequences:

- Count in both months → potential double-counting.
- Count in neither → potential under-counting.
- Attribute the chain to its root campaign → November activity is attributed to October.

Every send in this fixture falls between 3 and 20 October, so the issue is not exercised. It should be clarified before applying the logic to production data.

### 3.2 What happens when an ineligible campaign is the root of a retry chain?

Campaign `9004` is ineligible under the reporting rules and is also a leaf, so excluding it does not create an ambiguity.

The treatment becomes less clear if the **root** is ineligible but its descendants are eligible. For example, if `9001` were unapproved while `9002` and `9003` remained eligible, several interpretations are possible:

- Exclude the entire chain.
- Keep the eligible descendants as a chain.
- Treat the descendants as standalone campaigns, changing the counting grain from customers to attempts.

The current implementation applies the eligibility gate **inside the recursive chain walk**, so an ineligible campaign cannot carry its descendants into an eligible chain. This is a defensible interpretation, but the available documentation does not establish it as an explicit business rule.

---

## 4. Additional implementation observations

### Data quality

No data-quality adjustment is required for this reconciliation. All twelve integrity checks returned zero exceptions.

The full **30 → 22** difference is therefore explained by business rules and counting grain rather than by malformed or inconsistent data. That is worth calling out because many reconciliations combine data cleaning with rule application; this one does not.

### Timestamp representation

`sent_time` and `scheduled_time` are stored as text rather than date/time types. The October filter therefore relies on string comparison, which is valid here because the values use ISO-8601 formatting and therefore sort chronologically as strings.

The timestamps contain no timezone offset, so their interpretation depends on an assumed timezone.

In this fixture, `sent_time` and `scheduled_time` are identical for every row, so either field produces the same result. On production data, the distinction could matter—for example, when a send is scheduled in one month but actually occurs in the next.

---

## Takeaway

The fixture is sufficient to establish the **22-customer reconciliation**, but it does not exercise every documented rule. Several incorrect query variants also return 22, so the final result should be supported by the reconciliation logic and not by the number alone.

The remaining uncertainty is primarily **business-definition**, not SQL: the intended meaning of "reached," ownership of retry chains across reporting periods, and treatment of descendants of an ineligible root should be confirmed before production use.