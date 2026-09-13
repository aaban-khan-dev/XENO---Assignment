-- ============================================================
-- Phase 9: target_base
--
-- Per chain root, the counting rule depends on chain_type:
--   chained    -> COUNT(DISTINCT customer_id)
--                 the chain is one underlying communication, re-attempted;
--                 a customer reached after three tries was reached once
--   standalone -> COUNT(*)
--                 no chain exists, so each send is its own event
--
-- The metric is therefore a sum of two different aggregates over two
-- disjoint sets of roots. No single aggregate expresses it, which is why
-- Phase 7 showed 22 sitting between the two naive answers rather than at
-- either.
--
-- Parameterised on merchant and period via the scope CTE - change the
-- three literals there to run any merchant, any window.
-- ============================================================

WITH RECURSIVE scope AS (
    SELECT 501           AS merchant_id,
           '2026-10-01'  AS period_start,
           '2026-11-01'  AS period_end      -- half-open: [start, end)
),
eligible AS (
    SELECT c.*
    FROM campaign c, scope s
    WHERE c.merchant_id = s.merchant_id
      AND c.creation_status IN ('approved','aborted','resumed','stopped')
      AND c.processing_status = 'processed'
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
sends AS (
    -- Period and type filters applied here, against the log, so the
    -- graph walk above stays independent of send volume.
    SELECT ch.root_id, cs.n AS campaigns_in_chain, l.customer_id
    FROM chain ch
    JOIN chain_size cs ON cs.root_id = ch.root_id
    JOIN communication_log l ON l.communication_id = ch.campaign_id
    CROSS JOIN scope s
    WHERE l.merchant_id = s.merchant_id
      AND l.communication_type = '2'
      AND l.sent_time >= s.period_start
      AND l.sent_time <  s.period_end
),
per_root AS (
    SELECT
        root_id,
        campaigns_in_chain,
        CASE WHEN campaigns_in_chain > 1 THEN 'chained' ELSE 'standalone' END AS chain_type,
        COUNT(*)                      AS attempts,
        COUNT(DISTINCT customer_id)   AS distinct_customers,
        CASE WHEN campaigns_in_chain > 1
             THEN COUNT(DISTINCT customer_id)
             ELSE COUNT(*)
        END                           AS qualifying_sends
    FROM sends
    GROUP BY root_id, campaigns_in_chain
)

-- 9.1 Contribution per chain, then the total
-- sort_key exists only to place the TOTAL row last and is dropped by the
-- outer SELECT, since SQLite will not accept an expression in ORDER BY
-- after a compound UNION ALL.
SELECT root_id, chain_type, campaigns_in_chain,
       attempts, distinct_customers, qualifying_sends
FROM (

SELECT
    0                       AS sort_key,
    CAST(root_id AS TEXT)   AS root_id,
    chain_type,
    campaigns_in_chain,
    attempts,
    distinct_customers,
    qualifying_sends
FROM per_root

UNION ALL

SELECT 1, 'TOTAL', '', NULL, SUM(attempts), SUM(distinct_customers), SUM(qualifying_sends)
FROM per_root

ORDER BY 1, 2
);