-- Table inventory and storage Profiling

-- 1.1 Volume
-- quick view of size of each table.

SELECT 'campaign'          AS table_name, COUNT(*) AS rows FROM campaign
UNION ALL
SELECT 'communication_log' AS table_name, COUNT(*) AS rows FROM communication_log;


-- 1.2 Declared schema
-- validating table defination and column constraints

SELECT type, name, sql
FROM sqlite_master
WHERE type = 'table'
ORDER BY name;


-- 1.3 Access paths
-- check available indexes to ensure queries can be scaled efficiently

SELECT
    m.name        AS table_name,
    COALESCE(i.name, '(none)') AS index_name
FROM sqlite_master m
LEFT JOIN sqlite_master i
       ON i.type = 'index'
      AND i.tbl_name = m.name
WHERE m.type = 'table'
ORDER BY m.name, i.name;

-- 1.4 storage types and nulls
-- check how values are actually stored . 
-- look for NULL and mixed storage types 

SELECT 'campaign.id'                AS column_name, typeof(id)                AS storage_type, COUNT(*) AS n, SUM(id IS NULL)                AS nulls FROM campaign          GROUP BY 2
UNION ALL SELECT 'campaign.merchant_id',            typeof(merchant_id),        COUNT(*), SUM(merchant_id IS NULL)        FROM campaign          GROUP BY 2
UNION ALL SELECT 'campaign.parent_id',              typeof(parent_id),          COUNT(*), SUM(parent_id IS NULL)          FROM campaign          GROUP BY 2
UNION ALL SELECT 'campaign.name',                   typeof(name),               COUNT(*), SUM(name IS NULL)               FROM campaign          GROUP BY 2
UNION ALL SELECT 'campaign.creation_status',        typeof(creation_status),    COUNT(*), SUM(creation_status IS NULL)    FROM campaign          GROUP BY 2
UNION ALL SELECT 'campaign.processing_status',      typeof(processing_status),  COUNT(*), SUM(processing_status IS NULL)  FROM campaign          GROUP BY 2
UNION ALL SELECT 'comm_log.id',                     typeof(id),                 COUNT(*), SUM(id IS NULL)                 FROM communication_log GROUP BY 2
UNION ALL SELECT 'comm_log.merchant_id',            typeof(merchant_id),        COUNT(*), SUM(merchant_id IS NULL)        FROM communication_log GROUP BY 2
UNION ALL SELECT 'comm_log.communication_id',       typeof(communication_id),   COUNT(*), SUM(communication_id IS NULL)   FROM communication_log GROUP BY 2
UNION ALL SELECT 'comm_log.customer_id',            typeof(customer_id),        COUNT(*), SUM(customer_id IS NULL)        FROM communication_log GROUP BY 2
UNION ALL SELECT 'comm_log.communication_type',     typeof(communication_type), COUNT(*), SUM(communication_type IS NULL) FROM communication_log GROUP BY 2
UNION ALL SELECT 'comm_log.delivery_status',        typeof(delivery_status),    COUNT(*), SUM(delivery_status IS NULL)    FROM communication_log GROUP BY 2
UNION ALL SELECT 'comm_log.sent_time',              typeof(sent_time),          COUNT(*), SUM(sent_time IS NULL)          FROM communication_log GROUP BY 2
UNION ALL SELECT 'comm_log.scheduled_time',         typeof(scheduled_time),     COUNT(*), SUM(scheduled_time IS NULL)     FROM communication_log GROUP BY 2
UNION ALL SELECT 'comm_log.credit_used',            typeof(credit_used),        COUNT(*), SUM(credit_used IS NULL)        FROM communication_log GROUP BY 2
UNION ALL SELECT 'comm_log.channel',                typeof(channel),            COUNT(*), SUM(channel IS NULL)            FROM communication_log GROUP BY 2
ORDER BY 1, 2;