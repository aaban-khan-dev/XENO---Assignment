-- ============================================================
-- Phase 3: grain of communication_log
--
-- What does one row represent? The dictionary says one send attempt.
-- If that is right, a customer can appear more than once - and any
-- COUNT(*) is counting attempts, not people.
--
-- This determines whether the metric can be expressed as a single
-- aggregate at all.
-- ============================================================


-- 3.1 Is `id` the true grain?
-- If distinct ids equals row count, id is unique and the table has no
-- duplicate rows at the physical level.
SELECT
    COUNT(*)            AS total_rows,
    COUNT(DISTINCT id)  AS distinct_ids,
    CASE WHEN COUNT(*) = COUNT(DISTINCT id)
         THEN 'unique' ELSE 'DUPLICATES PRESENT' END AS verdict
FROM communication_log;


-- 3.2 Is (communication_id, customer_id) unique?
-- This is the grain question that matters. If a customer appears twice
-- against the same campaign, then one row is an attempt, not a person,
-- and the table cannot be counted as though it were one-per-customer.
SELECT
    COUNT(*)                                    AS distinct_pairs,
    (SELECT COUNT(*) FROM communication_log)    AS total_rows,
    (SELECT COUNT(*) FROM communication_log)
        - COUNT(*)                              AS excess_rows
FROM (
    SELECT DISTINCT communication_id, customer_id
    FROM communication_log
);


-- 3.3 Which pairs repeat, and where?
-- Locating the repeats matters more than counting them: a repeat inside
-- a retry chain means something different from a repeat inside a
-- campaign with no chain. This lists them with enough context to tell
-- the two cases apart later.
SELECT
    l.communication_id,
    c.name                      AS campaign_name,
    c.parent_id,
    l.customer_id,
    COUNT(*)                    AS attempts,
    MIN(l.sent_time)            AS first_attempt,
    MAX(l.sent_time)            AS last_attempt,
    COUNT(DISTINCT l.delivery_status) AS distinct_outcomes
FROM communication_log l
JOIN campaign c ON c.id = l.communication_id
GROUP BY l.communication_id, c.name, c.parent_id, l.customer_id
HAVING COUNT(*) > 1
ORDER BY l.communication_id, l.customer_id;


-- 3.4 Does the same customer appear under more than one campaign?
-- Repeats within a campaign are one pattern; the same customer across
-- several campaigns is another. If campaigns are chained, those rows
-- may be the same underlying communication re-attempted rather than
-- separate events. This is the shape that breaks a flat COUNT.
SELECT
    l.customer_id,
    COUNT(*)                              AS total_attempts,
    COUNT(DISTINCT l.communication_id)    AS campaigns_appeared_in,
    GROUP_CONCAT(DISTINCT l.communication_id) AS campaign_ids
FROM communication_log l
GROUP BY l.customer_id
HAVING COUNT(DISTINCT l.communication_id) > 1
ORDER BY total_attempts DESC, l.customer_id;


-- 3.5 Attempts vs distinct customers, per campaign
-- The gap between these two columns per campaign is the size of the
-- counting problem. Where they are equal, grain does not matter.
-- Where they differ, the choice of aggregate changes the answer.
SELECT
    c.id                                AS campaign_id,
    c.name,
    c.parent_id,
    c.creation_status,
    COUNT(l.id)                         AS attempts,
    COUNT(DISTINCT l.customer_id)       AS distinct_customers,
    COUNT(l.id) - COUNT(DISTINCT l.customer_id) AS gap
FROM campaign c
LEFT JOIN communication_log l ON l.communication_id = c.id
GROUP BY c.id, c.name, c.parent_id, c.creation_status
ORDER BY c.id;