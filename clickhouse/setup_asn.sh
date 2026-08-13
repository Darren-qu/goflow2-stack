#!/bin/bash
# Load IP→ASN (IPv4) into ClickHouse and enrich flows_raw src_as/dst_as when device AS is 0.
# Data: https://github.com/sapics/ip-location-db (iptoasn ASN, via sapics releases)
set -euo pipefail

CH_PASS="${CLICKHOUSE_PASSWORD:-flow}"
CH=(clickhouse-client --password "${CH_PASS}")
ASN_URL='https://github.com/sapics/ip-location-db/releases/download/latest/iptoasn-asn-ipv4-cidr.csv'
ASN_CSV='/var/lib/clickhouse/user_files/iptoasn-asn-ipv4-cidr.csv'

echo "[asn] creating tables..."
"${CH[@]}" -n <<SQL
CREATE TABLE IF NOT EXISTS asn
(
    cidr String,
    asn UInt32,
    as_org String
) ENGINE = MergeTree()
ORDER BY cidr;
SQL

echo "[asn] importing ASN CSV..."
"${CH[@]}" -q "TRUNCATE TABLE IF EXISTS asn"
mkdir -p /var/lib/clickhouse/user_files

download_ok=0
if command -v curl >/dev/null 2>&1; then
  if curl -fsSL -A 'goflow2-stack-asn' -o "${ASN_CSV}" "${ASN_URL}"; then
    download_ok=1
  fi
elif command -v wget >/dev/null 2>&1; then
  if wget -q -O "${ASN_CSV}" "${ASN_URL}"; then
    download_ok=1
  fi
fi

if [[ "${download_ok}" -eq 1 ]]; then
  ls -lh "${ASN_CSV}"
  head -n 2 "${ASN_CSV}" || true
  "${CH[@]}" -q "INSERT INTO asn FROM INFILE '${ASN_CSV}' FORMAT CSV"
else
  echo "[asn] curl/wget missing in container — fetching via ClickHouse url()"
  "${CH[@]}" -q "INSERT INTO asn SELECT cidr, asn, as_org FROM url('${ASN_URL}', CSV, 'cidr String, asn UInt32, as_org String')"
fi

ROWS=$("${CH[@]}" -q "SELECT count() FROM asn")
echo "[asn] cidr rows: ${ROWS}"
[[ "${ROWS}" -gt 1000 ]] || { echo "[asn] ERROR: too few ASN rows (${ROWS})" >&2; exit 1; }

echo "[asn] creating dictionary..."
# Escape single quotes in password for SQL literal
CH_PASS_SQL="${CH_PASS//\'/\'\'}"
"${CH[@]}" -n <<SQL
DROP DICTIONARY IF EXISTS asn_trie;

CREATE DICTIONARY asn_trie
(
    cidr String,
    asn UInt32,
    as_org String
)
PRIMARY KEY cidr
SOURCE(CLICKHOUSE(
    HOST 'localhost'
    PORT 9000
    USER 'default'
    PASSWORD '${CH_PASS_SQL}'
    TABLE 'asn'
    DB 'default'
))
LAYOUT(IP_TRIE)
LIFETIME(3600);
SQL

echo "[asn] test lookup 1.1.1.1:"
"${CH[@]}" -q "SELECT dictGet('asn_trie', ('asn','as_org'), toIPv4('1.1.1.1'))"

echo "[asn] enabling enrichment on flows_raw_view (device AS kept when non-zero)..."
"${CH[@]}" -n <<'SQL'
DROP TABLE IF EXISTS flows_raw_view;

CREATE MATERIALIZED VIEW flows_raw_view TO flows_raw
AS SELECT
    toDate(time_received_ns) AS date,
    now() AS time_inserted_ns,
    toDateTime64(time_received_ns/1000000000, 9) AS time_received_ns,
    toDateTime64(time_flow_start_ns/1000000000, 9) AS time_flow_start_ns,
    sequence_num,
    sampling_rate,
    sampler_address,

    src_addr,
    dst_addr,

    if(
        src_as != 0,
        src_as,
        if(
            etype = 2048,
            dictGetUInt32(
                'asn_trie',
                'asn',
                reinterpretAsUInt32(substring(reverse(src_addr), 13, 4))
            ),
            toUInt32(0)
        )
    ) AS src_as,
    if(
        dst_as != 0,
        dst_as,
        if(
            etype = 2048,
            dictGetUInt32(
                'asn_trie',
                'asn',
                reinterpretAsUInt32(substring(reverse(dst_addr), 13, 4))
            ),
            toUInt32(0)
        )
    ) AS dst_as,

    etype,
    proto,

    src_port,
    dst_port,

    bytes,
    packets
FROM flows;
SQL

echo "[asn] done. New flows get IP→ASN enrichment; historical rows keep prior src_as/dst_as."
echo "[asn] Attribution: ASN data via sapics/ip-location-db (iptoasn)."
