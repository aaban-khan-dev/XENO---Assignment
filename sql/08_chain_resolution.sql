-- ============================================================
-- Phase 8: Chain root resolution
--
-- Build the campaign-to-root mapping that will be used to group
-- sends belonging to the same retry chain.
-- ============================================================


-- 8.1 The mapping
-- Resolve each eligible campaign to its root and identify whether
-- it belongs to a retry chain or is standalone.
WITH RECURSIVE eligible AS (
    SELECT *
    FROM campaign
    WHERE creation_status IN ('approved','aborted','resumed','stopped')
      AND processing_status = 'processed'
),
chain(campaign_id, root_id, depth) AS (
    SELECT id, id, 1
    FROM eligible
    WHERE parent_id IS NULL

    UNION ALL

    SELECT e.id, ch.root_id, ch.depth + 1
    FROM eligible e
    JOIN chain ch ON e.parent_id = ch.campaign_id
    WHERE ch.depth < 100          -- cycle guard: parent_id is unconstrained
),
chain_size AS (
    SELECT root_id, COUNT(*) AS campaigns_in_chain
    FROM chain
    GROUP BY root_id
)
SELECT
    ch.campaign_id,
    ch.root_id,
    ch.depth,
    cs.campaigns_in_chain,
    CASE WHEN cs.campaigns_in_chain > 1 THEN 'chained' ELSE 'standalone' END AS chain_type,
    c.name AS campaign_name
FROM chain ch
JOIN chain_size cs ON cs.root_id = ch.root_id
JOIN campaign c    ON c.id = ch.campaign_id
ORDER BY ch.root_id, ch.depth, ch.campaign_id;


-- 8.2 Every eligible campaign is accounted for
-- Verify that every eligible campaign is connected to an eligible root
-- before using the mapping for the final count.
WITH RECURSIVE eligible AS (
    SELECT * FROM campaign
    WHERE creation_status IN ('approved','aborted','resumed','stopped')
      AND processing_status = 'processed'
),
chain(campaign_id) AS (
    SELECT id FROM eligible WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id FROM eligible e JOIN chain ch ON e.parent_id = ch.campaign_id
)
SELECT
    (SELECT COUNT(*) FROM eligible)                                  AS eligible_campaigns,
    (SELECT COUNT(*) FROM chain)                                     AS resolved_to_a_root,
    (SELECT COUNT(*) FROM eligible) - (SELECT COUNT(*) FROM chain)   AS unresolved,
    CASE WHEN (SELECT COUNT(*) FROM eligible) = (SELECT COUNT(*) FROM chain)
         THEN 'complete' ELSE 'INCOMPLETE - rows would be lost' END  AS verdict;