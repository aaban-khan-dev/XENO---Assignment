-- Phase 12: What this dataset can and cannot distinguish
--
-- Test a few alternative versions of the reconciliation to see
-- whether this dataset would expose an incorrect approach.
--
-- Getting 22 is not enough by itself. If an incorrect query also
-- returns 22, the data does not contain a case that would expose
-- that particular mistake.


-- 12.1 Compare the correct approach with several alternatives
--
-- The first version uses the full eligibility rules, recursively
-- resolves retry chains, and applies the appropriate counting rule
-- for chained and standalone campaigns.
--
-- The remaining versions intentionally change one part of the logic.
-- Comparing their results with the correct version shows which
-- assumptions actually matter in this dataset.
WITH RECURSIVE

-- Correct approach: full eligibility rules, recursive chain mapping,
-- and different counting rules for chained vs standalone campaigns.
c_elig AS (SELECT * FROM campaign
           WHERE creation_status IN ('approved','aborted','resumed','stopped')
             AND processing_status = 'processed'),
c_chain(cid, root, d) AS (
    SELECT id, id, 1 FROM c_elig WHERE parent_id IS NULL
    UNION ALL SELECT e.id, ch.root, ch.d+1 FROM c_elig e JOIN c_chain ch ON e.parent_id = ch.cid WHERE ch.d < 100),
c_sz AS (SELECT root, COUNT(*) n FROM c_chain GROUP BY root),
c_res AS (SELECT SUM(CASE WHEN n > 1 THEN dc ELSE att END) v FROM (
    SELECT s.n, COUNT(*) att, COUNT(DISTINCT l.customer_id) dc
    FROM c_chain ch JOIN c_sz s ON s.root = ch.root
    JOIN communication_log l ON l.communication_id = ch.cid
    GROUP BY ch.root, s.n)),


-- Incorrect approach: only treats 'approved' as finalized.
-- This would miss other valid finalized statuses if they existed.
n_elig AS (SELECT * FROM campaign
           WHERE creation_status = 'approved' AND processing_status = 'processed'),
n_chain(cid, root, d) AS (
    SELECT id, id, 1 FROM n_elig WHERE parent_id IS NULL
    UNION ALL SELECT e.id, ch.root, ch.d+1 FROM n_elig e JOIN n_chain ch ON e.parent_id = ch.cid WHERE ch.d < 100),
n_sz AS (SELECT root, COUNT(*) n FROM n_chain GROUP BY root),
n_res AS (SELECT SUM(CASE WHEN n > 1 THEN dc ELSE att END) v FROM (
    SELECT s.n, COUNT(*) att, COUNT(DISTINCT l.customer_id) dc
    FROM n_chain ch JOIN n_sz s ON s.root = ch.root
    JOIN communication_log l ON l.communication_id = ch.cid
    GROUP BY ch.root, s.n)),


-- Incorrect approach: ignores processing_status completely.
-- A campaign could therefore be counted before its processing is complete.
p_elig AS (SELECT * FROM campaign
           WHERE creation_status IN ('approved','aborted','resumed','stopped')),
p_chain(cid, root, d) AS (
    SELECT id, id, 1 FROM p_elig WHERE parent_id IS NULL
    UNION ALL SELECT e.id, ch.root, ch.d+1 FROM p_elig e JOIN p_chain ch ON e.parent_id = ch.cid WHERE ch.d < 100),
p_sz AS (SELECT root, COUNT(*) n FROM p_chain GROUP BY root),
p_res AS (SELECT SUM(CASE WHEN n > 1 THEN dc ELSE att END) v FROM (
    SELECT s.n, COUNT(*) att, COUNT(DISTINCT l.customer_id) dc
    FROM p_chain ch JOIN p_sz s ON s.root = ch.root
    JOIN communication_log l ON l.communication_id = ch.cid
    GROUP BY ch.root, s.n)),


-- Alternative interpretation: count only successful deliveries.
-- This tests whether target_base means customers actually delivered to
-- rather than customers who were targeted.
d_res AS (SELECT SUM(CASE WHEN n > 1 THEN dc ELSE att END) v FROM (
    SELECT s.n, COUNT(*) att, COUNT(DISTINCT l.customer_id) dc
    FROM c_chain ch JOIN c_sz s ON s.root = ch.root
    JOIN communication_log l ON l.communication_id = ch.cid
    WHERE l.delivery_status = 900
    GROUP BY ch.root, s.n)),


-- Incorrect approach: ignores the Diwali campaign scope.
-- The result shows whether that scope actually matters in this dataset.
f_res AS (SELECT SUM(CASE WHEN n > 1 THEN dc ELSE att END) v FROM (
    SELECT s.n, COUNT(*) att, COUNT(DISTINCT l.customer_id) dc
    FROM c_chain ch JOIN c_sz s ON s.root = ch.root
    JOIN campaign cm ON cm.id = ch.cid
    JOIN communication_log l ON l.communication_id = ch.cid
    WHERE cm.name LIKE '%Diwali%'
    GROUP BY ch.root, s.n))

SELECT 'a' AS v, 'correct: full gate, recursive walk, mixed grain' AS variant,
       (SELECT v FROM c_res) AS result, 'n/a' AS distinguishable
UNION ALL SELECT 'b', 'status list narrowed to approved only',
       (SELECT v FROM n_res),
       CASE WHEN (SELECT v FROM n_res) = (SELECT v FROM c_res) THEN 'NO' ELSE 'yes' END
UNION ALL SELECT 'c', 'processing_status condition dropped',
       (SELECT v FROM p_res),
       CASE WHEN (SELECT v FROM p_res) = (SELECT v FROM c_res) THEN 'NO' ELSE 'yes' END
UNION ALL SELECT 'd', 'delivered only (delivery_status = 900)',
       (SELECT v FROM d_res),
       CASE WHEN (SELECT v FROM d_res) = (SELECT v FROM c_res) THEN 'NO' ELSE 'yes' END
UNION ALL SELECT 'e', 'Diwali name filter applied',
       (SELECT v FROM f_res),
       CASE WHEN (SELECT v FROM f_res) = (SELECT v FROM c_res) THEN 'NO' ELSE 'yes' END
ORDER BY 1;


-- 12.2 Why some differences are not visible in this dataset
--
-- Check whether the data actually contains examples that would make
-- each alternative approach produce a different result.
--
-- A zero here does not mean the condition is unimportant. It means
-- this particular dataset does not test that condition.
SELECT 'campaigns with a finalized status other than approved' AS untested_condition,
       COUNT(*) AS rows_exercising_it,
       'aborted, resumed and stopped never appear' AS note
FROM campaign WHERE creation_status IN ('aborted','resumed','stopped')

UNION ALL SELECT 'campaigns not yet processed',
       COUNT(*), 'processing_status is constant at processed'
FROM campaign WHERE processing_status <> 'processed'

UNION ALL SELECT 'customers never successfully delivered to, in any chain',
       COUNT(*), 'every customer eventually gets a 900, so failures are always shadowed'
FROM (SELECT customer_id FROM communication_log
      GROUP BY customer_id HAVING SUM(CASE WHEN delivery_status = 900 THEN 1 ELSE 0 END) = 0)

UNION ALL SELECT 'campaigns whose name does not contain Diwali',
       COUNT(*), 'all 7 campaigns match, so the scope filter excludes nothing'
FROM campaign WHERE name NOT LIKE '%Diwali%'

UNION ALL SELECT 'sends outside the October window',
       COUNT(*), 'period filter excludes nothing'
FROM communication_log
WHERE sent_time < '2026-10-01' OR sent_time >= '2026-11-01';