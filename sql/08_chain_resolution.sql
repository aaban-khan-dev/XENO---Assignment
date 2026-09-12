-- ============================================================
-- Phase 8: chain root resolution
--
-- Produces the mapping every later query depends on: eligible campaign
-- -> chain root, with the chained/standalone flag that selects the
-- counting rule.
--
-- Deliberately isolated from communication_log. The recursion walks
-- `campaign` only, which grows with marketing activity rather than send
-- volume - on production data this side stays small while the log grows
-- without bound. Keeping the graph walk separate from the fact join is
-- what lets the mapping be materialised and refreshed on campaign
-- change, instead of re-derived on every report run. See Phase 14.
-- ============================================================


-- 8.1 The mapping
-- Eligibility is applied INSIDE the recursion, so an ineligible campaign
-- is excluded and cannot carry its descendants into a chain. Here 9004
-- is a leaf so this makes no difference - but on data where an
-- ineligible campaign sits mid-chain, filtering after the walk would
-- silently attach its children to a root they no longer descend from
-- through eligible campaigns.
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
-- The recursion starts from parent_id IS NULL. If an eligible campaign
-- were unreachable from any eligible root - because its parent was
-- excluded by the gate, or because of a cycle - it would be dropped
-- here and its log rows would vanish from the total without any error.
-- This confirms the mapping is complete before anything is counted on
-- top of it.
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