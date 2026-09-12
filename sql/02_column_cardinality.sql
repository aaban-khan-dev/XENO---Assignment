
-- Phase 2: column cardinality and constant detection
-- checking which columns actually vary in the dataset


-- 2.1 Distinct value counts per column
-- checking which columns have variation and which are constant.

SELECT 'campaign.merchant_id'          AS column_name, COUNT(DISTINCT merchant_id)       AS n_distinct FROM campaign
UNION ALL SELECT 'campaign.parent_id',           COUNT(DISTINCT parent_id)        FROM campaign
UNION ALL SELECT 'campaign.name',                COUNT(DISTINCT name)             FROM campaign
UNION ALL SELECT 'campaign.creation_status',     COUNT(DISTINCT creation_status)  FROM campaign
UNION ALL SELECT 'campaign.processing_status',   COUNT(DISTINCT processing_status) FROM campaign
UNION ALL SELECT 'comm_log.merchant_id',         COUNT(DISTINCT merchant_id)       FROM communication_log
UNION ALL SELECT 'comm_log.communication_id',    COUNT(DISTINCT communication_id)  FROM communication_log
UNION ALL SELECT 'comm_log.customer_id',         COUNT(DISTINCT customer_id)       FROM communication_log
UNION ALL SELECT 'comm_log.communication_type',  COUNT(DISTINCT communication_type) FROM communication_log
UNION ALL SELECT 'comm_log.delivery_status',     COUNT(DISTINCT delivery_status)   FROM communication_log
UNION ALL SELECT 'comm_log.credit_used',         COUNT(DISTINCT credit_used)       FROM communication_log
UNION ALL SELECT 'comm_log.channel',             COUNT(DISTINCT channel)           FROM communication_log
ORDER BY n_distinct, column_name;


-- 2.2 Value distribution on the low-cardinality columns
-- inspecting actual values and their frequencies 

SELECT 'creation_status'   AS column_name, creation_status    AS value, COUNT(*) AS n FROM campaign          GROUP BY 2
UNION ALL SELECT 'processing_status',      processing_status,           COUNT(*) FROM campaign          GROUP BY 2
UNION ALL SELECT 'delivery_status',        CAST(delivery_status AS TEXT), COUNT(*) FROM communication_log GROUP BY 2
UNION ALL SELECT 'communication_type',     communication_type,          COUNT(*) FROM communication_log GROUP BY 2
UNION ALL SELECT 'channel',                channel,                     COUNT(*) FROM communication_log GROUP BY 2
UNION ALL SELECT 'credit_used',            CAST(credit_used AS TEXT),   COUNT(*) FROM communication_log GROUP BY 2
ORDER BY column_name, n DESC;


-- 2.3 Does the "Diwali" scope filter actually discriminate?
-- checks whether "Diwali" as campaign name filter excludes any anything
SELECT
    COUNT(*)                                          AS campaigns_total,
    SUM(CASE WHEN name LIKE '%Diwali%' THEN 1 ELSE 0 END) AS name_matches_diwali,
    COUNT(DISTINCT merchant_id)                       AS distinct_merchants
FROM campaign;


-- 2.4 Time coverage
-- Confirms the October window and whether sent_time and scheduled_time ever diverge
SELECT
    MIN(sent_time)                                              AS first_sent,
    MAX(sent_time)                                              AS last_sent,
    SUM(CASE WHEN sent_time <> scheduled_time THEN 1 ELSE 0 END) AS rows_where_times_differ,
    SUM(CASE WHEN sent_time <  '2026-10-01'
              OR sent_time >= '2026-11-01' THEN 1 ELSE 0 END)    AS rows_outside_october
FROM communication_log;