-- Phase 6: Integrity checks
--
-- Check for data issues that could affect the reconciliation or cause
-- records to be incorrectly included, excluded, or counted twice.


-- Check each potential integrity issue and record how many affected rows
-- are present. Zero results are useful because they rule out possible
-- explanations for the difference in the final count.
SELECT
    'log rows with no matching campaign'                    AS check_name,
    COUNT(*)                                                AS found,
    'would be dropped by an inner join, silently'           AS impact_if_present
FROM communication_log l
LEFT JOIN campaign c ON c.id = l.communication_id
WHERE c.id IS NULL

UNION ALL SELECT
    'log rows whose merchant differs from their campaign',
    COUNT(*),
    'attributes sends to the wrong merchant'
FROM communication_log l
JOIN campaign c ON c.id = l.communication_id
WHERE l.merchant_id <> c.merchant_id

UNION ALL SELECT
    'parent_id crossing merchant boundary',
    COUNT(*),
    'chain would span merchants, breaking per-merchant scoping'
FROM campaign c
JOIN campaign p ON p.id = c.parent_id
WHERE c.merchant_id <> p.merchant_id

UNION ALL SELECT
    'customer_id with leading or trailing whitespace',
    COUNT(*),
    'same customer counted twice in a DISTINCT'
FROM communication_log
WHERE customer_id <> TRIM(customer_id)

UNION ALL SELECT
    'customer_id pairs differing only by case or whitespace',
    COUNT(*),
    'same customer counted twice in a DISTINCT'
FROM (SELECT DISTINCT customer_id FROM communication_log) a
JOIN (SELECT DISTINCT customer_id FROM communication_log) b
  ON LOWER(TRIM(a.customer_id)) = LOWER(TRIM(b.customer_id))
 AND a.customer_id <> b.customer_id

UNION ALL SELECT
    'empty or whitespace-only customer_id',
    COUNT(*),
    'collapses to a single phantom customer in a DISTINCT'
FROM communication_log
WHERE TRIM(customer_id) = ''

UNION ALL SELECT
    'sent_time not parseable as a date',
    COUNT(*),
    'string range filter on the period would misbehave'
FROM communication_log
WHERE DATE(sent_time) IS NULL

UNION ALL SELECT
    'sent_time outside October 2026',
    COUNT(*),
    'out of the reporting period'
FROM communication_log
WHERE sent_time < '2026-10-01' OR sent_time >= '2026-11-01'

UNION ALL SELECT
    'sent_time earlier than scheduled_time',
    COUNT(*),
    'sent before scheduled - timestamp integrity problem'
FROM communication_log
WHERE sent_time < scheduled_time

UNION ALL SELECT
    'sent and scheduled falling in different months',
    COUNT(*),
    'period membership depends on which column is chosen'
FROM communication_log
WHERE SUBSTR(sent_time, 1, 7) <> SUBSTR(scheduled_time, 1, 7)

UNION ALL SELECT
    'delivery_status outside the documented set',
    COUNT(*),
    'undocumented outcome, treatment unclear'
FROM communication_log
WHERE delivery_status NOT IN (900, 1100)

UNION ALL SELECT
    'campaigns with no log rows at all',
    COUNT(*),
    'campaign exists but never sent - contributes zero'
FROM campaign c
WHERE NOT EXISTS (
    SELECT 1 FROM communication_log l WHERE l.communication_id = c.id
)

ORDER BY found DESC, check_name;