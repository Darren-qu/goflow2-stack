#!/bin/bash
# Apply / refresh ClickHouse TTL for flow tables (idempotent).
# Defaults match ops practice: detail 30d, 5m aggregates 180d.
# Override via env: FLOWS_RAW_TTL_DAYS, FLOWS_5M_TTL_DAYS, CLICKHOUSE_PASSWORD
set -euo pipefail

RAW_DAYS="${FLOWS_RAW_TTL_DAYS:-30}"
AGG_DAYS="${FLOWS_5M_TTL_DAYS:-180}"
CH_PASS="${CLICKHOUSE_PASSWORD:-flow}"

CH=(clickhouse-client --password "${CH_PASS}")

echo "[retention] flows_raw TTL = ${RAW_DAYS} day(s); flows_5m TTL = ${AGG_DAYS} day(s)"

# Separate ALTERs: combined MODIFY TTL + MODIFY SETTING fails on CH 25.x
# date partition + ttl_only_drop_parts → drop whole day parts when expired (cheap)
"${CH[@]}" -n <<-EOSQL
    ALTER TABLE flows_raw
        MODIFY TTL date + toIntervalDay(${RAW_DAYS});
    ALTER TABLE flows_raw
        MODIFY SETTING ttl_only_drop_parts = 1;

    ALTER TABLE flows_5m
        MODIFY TTL date + toIntervalDay(${AGG_DAYS});
    ALTER TABLE flows_5m
        MODIFY SETTING ttl_only_drop_parts = 1;
EOSQL

echo "[retention] OK — ClickHouse merges will drop expired partitions automatically"
echo "[retention] disk check:"
"${CH[@]}" -q "
SELECT
    table,
    formatReadableSize(sum(bytes_on_disk)) AS on_disk,
    min(partition) AS oldest_part,
    max(partition) AS newest_part,
    count() AS parts
FROM system.parts
WHERE active AND database = currentDatabase() AND table IN ('flows_raw', 'flows_5m')
GROUP BY table
ORDER BY table
"
