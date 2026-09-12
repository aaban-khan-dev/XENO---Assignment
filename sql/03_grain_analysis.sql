-- Phase 3: grain of communication_log
--
-- determining what one row of a table represents


-- 3.1 Is id unique?
-- check whether each row has unique id. 

SELECT
    COUNT(*)            AS total_rows,
    COUNT(DISTINCT id)  AS distinct_ids,
    CASE WHEN COUNT(*) = COUNT(DISTINCT id)
         THEN 'unique' ELSE 'DUPLICATES PRESENT' END AS verdict
FROM communication_log;

-- 3.2 Is (communication_id, customer_id) unique?
-- check whetehr same customer have multiple attempts for same campaign.

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
-- Identify repeating customer-campaign pairs and inspect their context

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
-- comparing send attempts with distinct customers to see 
-- if any campaign has multiple attempts per customer

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