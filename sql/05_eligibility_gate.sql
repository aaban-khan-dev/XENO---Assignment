-- ============================================================
-- Phase 5: the reporting eligibility gate
--
-- The data dictionary defines a campaign as reportable only when both
-- workflows have finished:
--   creation_status   IN ('approved','aborted','resumed','stopped')
--   processing_status =  'processed'
--
-- The two run independently - the dictionary notes the send pipeline can
-- run ahead of approval bookkeeping. So log rows can exist for a campaign
-- that is not yet reportable.
-- ============================================================


-- 5.1 Status cross-tab, with log volume attached
-- Campaign counts alone understate the impact. What matters is how many
-- log rows sit behind each status combination.
SELECT
    c.creation_status,
    c.processing_status,
    COUNT(DISTINCT c.id)    AS campaigns,
    COUNT(l.id)             AS log_rows,
    CASE
        WHEN c.creation_status IN ('approved','aborted','resumed','stopped')
         AND c.processing_status = 'processed'
        THEN 'eligible' ELSE 'EXCLUDED'
    END                     AS gate
FROM campaign c
LEFT JOIN communication_log l ON l.communication_id = c.id
GROUP BY c.creation_status, c.processing_status
ORDER BY gate, c.creation_status;


-- 5.2 Which campaigns fail the gate, and what do they carry?
-- The excluded rows are otherwise unremarkable - they have real
-- customers and successful deliveries. Nothing in communication_log
-- marks them as non-reportable. Only the join to campaign reveals it.
SELECT
    c.id                            AS campaign_id,
    c.name,
    c.parent_id,
    c.creation_status,
    c.processing_status,
    COUNT(l.id)                     AS log_rows,
    COUNT(DISTINCT l.customer_id)   AS distinct_customers,
    SUM(CASE WHEN l.delivery_status = 900 THEN 1 ELSE 0 END) AS delivered
FROM campaign c
LEFT JOIN communication_log l ON l.communication_id = c.id
WHERE NOT (
        c.creation_status IN ('approved','aborted','resumed','stopped')
    AND c.processing_status = 'processed'
)
GROUP BY c.id, c.name, c.parent_id, c.creation_status, c.processing_status
ORDER BY c.id;


-- 5.3 Does each half of the gate discriminate on this data?
-- Tests the two conditions separately. A condition that excludes nothing
-- is untested by this fixture: a query omitting it would be wrong in
-- production and indistinguishable from a correct one here.
SELECT
    'creation_status in finalized set'  AS condition,
    SUM(CASE WHEN creation_status IN ('approved','aborted','resumed','stopped')
             THEN 0 ELSE 1 END)         AS campaigns_excluded
FROM campaign
UNION ALL
SELECT
    'processing_status = processed',
    SUM(CASE WHEN processing_status = 'processed' THEN 0 ELSE 1 END)
FROM campaign
UNION ALL
SELECT
    'creation_status = approved (narrow, incorrect)',
    SUM(CASE WHEN creation_status = 'approved' THEN 0 ELSE 1 END)
FROM campaign;


-- 5.4 Where does the excluded campaign sit in the graph?
-- An excluded campaign that is a chain leaf can simply be dropped. An
-- excluded chain ROOT would be a harder question: do its eligible
-- children form their own chain, or disappear with it? Worth knowing
-- which case this fixture presents.
WITH RECURSIVE chain(campaign_id, root_id, depth) AS (
    SELECT id, id, 1 FROM campaign WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, ch.root_id, ch.depth + 1
    FROM campaign c JOIN chain ch ON c.parent_id = ch.campaign_id
    WHERE ch.depth < 100
),
children AS (
    SELECT parent_id, COUNT(*) AS n FROM campaign
    WHERE parent_id IS NOT NULL GROUP BY parent_id
)
SELECT
    ch.campaign_id,
    ch.root_id,
    ch.depth,
    c.creation_status,
    COALESCE(ki.n, 0)   AS direct_children,
    CASE WHEN ch.campaign_id = ch.root_id THEN 'root'
         WHEN COALESCE(ki.n, 0) = 0       THEN 'leaf'
         ELSE                                  'internal' END AS position
FROM chain ch
JOIN campaign c   ON c.id = ch.campaign_id
LEFT JOIN children ki ON ki.parent_id = ch.campaign_id
WHERE c.creation_status NOT IN ('approved','aborted','resumed','stopped')
   OR c.processing_status <> 'processed';