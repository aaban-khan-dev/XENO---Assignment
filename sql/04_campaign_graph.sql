-- Phase 4: Structure of the campaign retry graph
--
-- Understand how campaigns are connected through parent_id and
-- determine the depth and structure of the retry chains.



-- 4.1 Node classification
-- Classify campaigns based on their parent and child relationships
-- to identify standalone campaigns and retry chains.

SELECT
    CASE
        WHEN c.parent_id IS NULL AND COALESCE(ch.child_count, 0) = 0 THEN 'standalone (no chain)'
        WHEN c.parent_id IS NULL                                     THEN 'chain root'
        WHEN COALESCE(ch.child_count, 0) = 0                         THEN 'chain leaf'
        ELSE                                                 'chain internal'
    END                     AS node_type,
    COUNT(*)                AS n,
    GROUP_CONCAT(c.id)      AS campaign_ids
FROM campaign c
LEFT JOIN (
    SELECT parent_id, COUNT(*) AS child_count
    FROM campaign
    WHERE parent_id IS NOT NULL
    GROUP BY parent_id
) ch ON ch.parent_id = c.id
GROUP BY node_type
ORDER BY node_type;


-- 4.2 Branching factor
-- Check whether a campaign has multiple retry children, which would
-- make the retry structure a tree rather than a simple chain.

SELECT
    parent_id           AS campaign_id,
    COUNT(*)            AS direct_children,
    GROUP_CONCAT(id)    AS child_ids
FROM campaign
WHERE parent_id IS NOT NULL
GROUP BY parent_id
ORDER BY direct_children DESC, parent_id;


-- 4.3 Resolve every campaign to its root, with depth
-- Trace each campaign back to its original campaign and record its
-- position in the retry chain.
WITH RECURSIVE chain(campaign_id, root_id, depth, path) AS (
    SELECT id, id, 1, CAST(id AS TEXT)
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    SELECT c.id, ch.root_id, ch.depth + 1, ch.path || ' -> ' || CAST(c.id AS TEXT)
    FROM campaign c
    JOIN chain ch ON c.parent_id = ch.campaign_id
    WHERE ch.depth < 100
)
SELECT campaign_id, root_id, depth, path
FROM chain
ORDER BY root_id, depth, campaign_id;


-- 4.4 Chain summary: size and maximum depth per root
-- Summarize each retry group and check the maximum depth to determine
-- whether a simple join is sufficient or recursion is needed.

WITH RECURSIVE chain(campaign_id, root_id, depth) AS (
    SELECT id, id, 1 FROM campaign WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, ch.root_id, ch.depth + 1
    FROM campaign c JOIN chain ch ON c.parent_id = ch.campaign_id
    WHERE ch.depth < 100
)
SELECT
    ch.root_id,
    c.name                  AS root_name,
    COUNT(*)                AS campaigns_in_chain,
    MAX(ch.depth)           AS max_depth,
    CASE WHEN COUNT(*) = 1 THEN 'standalone' ELSE 'chained' END AS chain_type
FROM chain ch
JOIN campaign c ON c.id = ch.root_id
GROUP BY ch.root_id, c.name
ORDER BY ch.root_id;


-- 4.5 Orphaned and cyclic nodes
-- Check for broken parent references and campaigns that cannot be
-- reached from a root.

SELECT 'parent_id points at missing campaign' AS issue,
       COUNT(*)                               AS n,
       COALESCE(GROUP_CONCAT(c.id), '')       AS campaign_ids
FROM campaign c
LEFT JOIN campaign p ON p.id = c.parent_id
WHERE c.parent_id IS NOT NULL AND p.id IS NULL

UNION ALL

SELECT 'campaign unreachable from any root',
       COUNT(*),
       COALESCE(GROUP_CONCAT(id), '')
FROM campaign
WHERE id NOT IN (
    WITH RECURSIVE chain(campaign_id) AS (
        SELECT id FROM campaign WHERE parent_id IS NULL
        UNION ALL
        SELECT c.id FROM campaign c JOIN chain ch ON c.parent_id = ch.campaign_id
    )
    SELECT campaign_id FROM chain
);