-- ============================================================
-- Phase 7: Naive baselines
--
-- Calculate the obvious baseline counts and compare them with
-- Finance's target_base of 22.
-- ============================================================


-- 7.1 The four obvious one-line answers
-- Compare attempts and distinct customers under both the full dataset
-- and eligible-campaign scope.
SELECT 'all attempts'                      AS approach, COUNT(*)                   AS result FROM communication_log
UNION ALL
SELECT 'all distinct customers',                        COUNT(DISTINCT customer_id)       FROM communication_log
UNION ALL
SELECT 'attempts, eligible campaigns only',             COUNT(*)
FROM communication_log l JOIN campaign c ON c.id = l.communication_id
WHERE c.creation_status IN ('approved','aborted','resumed','stopped')
  AND c.processing_status = 'processed'
UNION ALL
SELECT 'distinct customers, eligible only',             COUNT(DISTINCT l.customer_id)
FROM communication_log l JOIN campaign c ON c.id = l.communication_id
WHERE c.creation_status IN ('approved','aborted','resumed','stopped')
  AND c.processing_status = 'processed';


-- 7.2 Can any filter close the gap?
-- Compare the eligible attempts and distinct-customer counts with
-- Finance's target to determine whether filtering alone can explain
-- the difference.
WITH eligible AS (
    SELECT l.*
    FROM communication_log l
    JOIN campaign c ON c.id = l.communication_id
    WHERE c.creation_status IN ('approved','aborted','resumed','stopped')
      AND c.processing_status = 'processed'
)
SELECT
    (SELECT COUNT(*) FROM eligible)                     AS attempts,
    (SELECT COUNT(DISTINCT customer_id) FROM eligible)  AS distinct_customers,
    22                                                  AS finance_reports,
    (SELECT COUNT(*) FROM eligible) - 22                AS attempts_above_target,
    22 - (SELECT COUNT(DISTINCT customer_id) FROM eligible) AS target_above_distinct;


-- 7.3 Where the two aggregates disagree, by chain
-- Compare attempts and distinct customers within each retry group
-- to locate where repeated attempts are affecting the count.
WITH RECURSIVE chain(campaign_id, root_id) AS (
    SELECT id, id FROM campaign WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, ch.root_id
    FROM campaign c JOIN chain ch ON c.parent_id = ch.campaign_id
),
eligible AS (
    SELECT id FROM campaign
    WHERE creation_status IN ('approved','aborted','resumed','stopped')
      AND processing_status = 'processed'
)
SELECT
    ch.root_id,
    cr.name                                     AS root_name,
    COUNT(DISTINCT ch.campaign_id)              AS campaigns_in_chain,
    COUNT(l.id)                                 AS attempts,
    COUNT(DISTINCT l.customer_id)               AS distinct_customers,
    COUNT(l.id) - COUNT(DISTINCT l.customer_id) AS repeats
FROM chain ch
JOIN eligible e   ON e.id = ch.campaign_id
JOIN campaign cr  ON cr.id = ch.root_id
LEFT JOIN communication_log l ON l.communication_id = ch.campaign_id
GROUP BY ch.root_id, cr.name
ORDER BY ch.root_id;