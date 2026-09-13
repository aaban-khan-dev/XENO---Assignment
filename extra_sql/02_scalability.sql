-- Phase 13: Scalability and query plan checks
--
-- The dataset is small, so runtime measurements would not tell us
-- much about how the query behaves on a larger production table.
-- Instead, inspect SQLite's query plan and test useful indexes.


-- 13.1 Query plan for the final reconciliation
-- Check how SQLite accesses the log and campaign tables.

EXPLAIN QUERY PLAN
WITH RECURSIVE
eligible_campaigns AS (
    SELECT id, parent_id
    FROM campaign
    WHERE merchant_id = 501
      AND creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND processing_status = 'processed'
),
chain AS (
    SELECT id AS campaign_id, id AS root_id, 1 AS depth
    FROM eligible_campaigns
    WHERE parent_id IS NULL

    UNION ALL

    SELECT c.id, ch.root_id, ch.depth + 1
    FROM eligible_campaigns c
    JOIN chain ch ON c.parent_id = ch.campaign_id
    WHERE ch.depth < 100  -- safety limit for unexpected cycles
),
log_data AS (
    SELECT cl.communication_id, cl.customer_id, ch.root_id
    FROM communication_log cl
    JOIN chain ch ON ch.campaign_id = cl.communication_id
    WHERE cl.merchant_id = 501
      AND cl.communication_type = '2'
      AND cl.sent_time >= '2026-10-01'
      AND cl.sent_time < '2026-11-01'
)
SELECT COUNT(*)
FROM (
    SELECT root_id, customer_id
    FROM log_data
    GROUP BY root_id, customer_id
);


-- 13.2 Query plan for the retry-chain walk
-- Check the campaign-side recursion separately from the log table.

EXPLAIN QUERY PLAN
WITH RECURSIVE
eligible_campaigns AS (
    SELECT id, parent_id
    FROM campaign
    WHERE merchant_id = 501
      AND creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND processing_status = 'processed'
),
chain AS (
    SELECT id AS campaign_id, id AS root_id, 1 AS depth
    FROM eligible_campaigns
    WHERE parent_id IS NULL

    UNION ALL

    SELECT c.id, ch.root_id, ch.depth + 1
    FROM eligible_campaigns c
    JOIN chain ch ON c.parent_id = ch.campaign_id
    WHERE ch.depth < 100  -- safety limit for unexpected cycles
)
SELECT *
FROM chain;


-- 13.3 Query plan for the log-side filter
-- Check how SQLite accesses communication_log before adding indexes.

EXPLAIN QUERY PLAN
SELECT communication_id, customer_id
FROM communication_log
WHERE merchant_id = 501
  AND communication_type = '2'
  AND sent_time >= '2026-10-01'
  AND sent_time < '2026-11-01';


-- 13.4 Test indexes
-- Add indexes that support the main filters and joins, then
-- compare the query plans again.
--
-- These are temporary test indexes and are removed in 13.5.

CREATE INDEX idx_log_covering
ON communication_log (
    merchant_id,
    sent_time,
    communication_id,
    customer_id
);

CREATE INDEX idx_campaign_parent
ON campaign (parent_id);


-- Re-check the log-side access path after adding the test index.

EXPLAIN QUERY PLAN
SELECT communication_id, customer_id
FROM communication_log
WHERE merchant_id = 501
  AND communication_type = '2'
  AND sent_time >= '2026-10-01'
  AND sent_time < '2026-11-01';


-- Re-check the full reconciliation plan with the test indexes.

EXPLAIN QUERY PLAN
WITH RECURSIVE
eligible_campaigns AS (
    SELECT id, parent_id
    FROM campaign
    WHERE merchant_id = 501
      AND creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND processing_status = 'processed'
),
chain AS (
    SELECT id AS campaign_id, id AS root_id, 1 AS depth
    FROM eligible_campaigns
    WHERE parent_id IS NULL

    UNION ALL

    SELECT c.id, ch.root_id, ch.depth + 1
    FROM eligible_campaigns c
    JOIN chain ch ON c.parent_id = ch.campaign_id
    WHERE ch.depth < 100  -- safety limit for unexpected cycles
),
log_data AS (
    SELECT cl.communication_id, cl.customer_id, ch.root_id
    FROM communication_log cl
    JOIN chain ch ON ch.campaign_id = cl.communication_id
    WHERE cl.merchant_id = 501
      AND cl.communication_type = '2'
      AND cl.sent_time >= '2026-10-01'
      AND cl.sent_time < '2026-11-01'
)
SELECT COUNT(*)
FROM (
    SELECT root_id, customer_id
    FROM log_data
    GROUP BY root_id, customer_id
);


-- 13.5 Restore the supplied database
-- Remove the test indexes so no permanent schema changes remain.

DROP INDEX idx_log_covering;
DROP INDEX idx_campaign_parent;