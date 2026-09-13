-- ============================================================
-- Phase 11: reconciliation bridge
--
-- Each step is computed, not asserted. Every value below comes from a
-- query against comm_log.db rather than a hardcoded literal, so the
-- table can be re-run and will still reconcile if the data changes.
--
-- Step order follows the order the adjustments were established:
--   the eligibility gate (Phase 5) before chain collapsing (Phases 7-8),
--   because chain membership is defined over eligible campaigns only.
--
-- No data-quality adjustments appear here. Phase 6 ran twelve integrity
-- checks and all returned zero, so the entire gap between 30 and 22 is
-- definitional.
-- ============================================================

WITH RECURSIVE eligible AS (
    SELECT * FROM campaign
    WHERE creation_status IN ('approved','aborted','resumed','stopped')
      AND processing_status = 'processed'
),
chain(campaign_id, root_id, depth) AS (
    SELECT id, id, 1 FROM eligible WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, ch.root_id, ch.depth + 1
    FROM eligible e JOIN chain ch ON e.parent_id = ch.campaign_id
    WHERE ch.depth < 100
),
chain_size AS (
    SELECT root_id, COUNT(*) AS n FROM chain GROUP BY root_id
),
per_root AS (
    SELECT
        ch.root_id,
        cs.n                                        AS campaigns_in_chain,
        COUNT(l.id)                                 AS attempts,
        COUNT(DISTINCT l.customer_id)               AS distinct_customers,
        COUNT(l.id) - COUNT(DISTINCT l.customer_id) AS repeats
    FROM chain ch
    JOIN chain_size cs ON cs.root_id = ch.root_id
    JOIN communication_log l ON l.communication_id = ch.campaign_id
    GROUP BY ch.root_id, cs.n
),
step0 AS (SELECT COUNT(*) AS v FROM communication_log),
step1 AS (SELECT SUM(attempts) AS v FROM per_root),
step2 AS (SELECT (SELECT v FROM step1)
                 - (SELECT repeats FROM per_root WHERE root_id = 9001) AS v),
step3 AS (SELECT (SELECT v FROM step2)
                 - (SELECT repeats FROM per_root WHERE root_id = 9201) AS v),
final AS (SELECT (SELECT v FROM step3) AS v)

SELECT 0                                                  AS sort_key,
       '0'                                                AS step,
       'Every row in communication_log'                   AS description,
       (SELECT v FROM step0)                              AS result,
       ''                                                 AS change,
       'Starting point: one row per send attempt'         AS reason

UNION ALL SELECT 1,
       '1',
       'Exclude campaigns that failed the reporting gate',
       (SELECT v FROM step1),
       '-' || ((SELECT v FROM step0) - (SELECT v FROM step1)),
       '9004 is approval_awaiting, so not signed off and not reportable'

UNION ALL SELECT 2,
       '2',
       'Collapse retries within chain 9001 -> 9002 -> 9003',
       (SELECT v FROM step2),
       '-' || (SELECT repeats FROM per_root WHERE root_id = 9001),
       'C2 and C3 re-attempted after failure, same communication'

UNION ALL SELECT 3,
       '3',
       'Collapse retries within chain 9201 -> 9202',
       (SELECT v FROM step3),
       '-' || (SELECT repeats FROM per_root WHERE root_id = 9201),
       'D1 re-attempted after failure'

UNION ALL SELECT 9,
       'final',
       'Leave 9101 uncollapsed (standalone, no retry chain)',
       (SELECT v FROM final),
       '0',
       'C20 delivered twice 10 days apart with no failure, so not a retry'

ORDER BY 1;