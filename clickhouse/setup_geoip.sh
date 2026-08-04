#!/bin/bash
# Load DB-IP city (IPv4) into ClickHouse and build ip_trie dictionary for map panels.
# Data: https://github.com/sapics/ip-location-db (DB-IP Lite, CC BY 4.0)
set -euo pipefail

CH=(clickhouse-client --password flow)
GEO_URL='https://github.com/sapics/ip-location-db/releases/download/latest/dbip-city-ipv4.csv.gz'
GEO_GZ='/var/lib/clickhouse/user_files/dbip-city-ipv4.gz'
GEO_CSV='/var/lib/clickhouse/user_files/dbip-city-ipv4.csv'

echo "[geoip] downloading DB-IP city IPv4..."
mkdir -p /var/lib/clickhouse/user_files
curl -fsSL -o "${GEO_GZ}" "${GEO_URL}"
gzip -df "${GEO_GZ}" || gunzip -f "${GEO_GZ}"
# gzip -d may leave dbip-city-ipv4 without .csv
if [ -f /var/lib/clickhouse/user_files/dbip-city-ipv4 ] && [ ! -f "${GEO_CSV}" ]; then
  mv /var/lib/clickhouse/user_files/dbip-city-ipv4 "${GEO_CSV}"
fi
ls -lh "${GEO_CSV}"
head -n 2 "${GEO_CSV}" || true

echo "[geoip] creating tables..."
"${CH[@]}" -n <<'SQL'
CREATE TABLE IF NOT EXISTS geoip_raw
(
    ip_range_start IPv4,
    ip_range_end IPv4,
    country_code Nullable(String),
    state1 Nullable(String),
    state2 Nullable(String),
    city Nullable(String),
    postcode Nullable(String),
    latitude Float64,
    longitude Float64,
    timezone Nullable(String)
) ENGINE = MergeTree()
ORDER BY ip_range_start;

CREATE TABLE IF NOT EXISTS geoip
(
    cidr String,
    latitude Float64,
    longitude Float64,
    country_code String,
    city String
) ENGINE = MergeTree()
ORDER BY cidr;
SQL

echo "[geoip] importing CSV..."
"${CH[@]}" -q "TRUNCATE TABLE IF EXISTS geoip_raw"
"${CH[@]}" -q "TRUNCATE TABLE IF EXISTS geoip"
"${CH[@]}" -q "INSERT INTO geoip_raw FROM INFILE '${GEO_CSV}' FORMAT CSV"

RAW=$("${CH[@]}" -q "SELECT count() FROM geoip_raw")
echo "[geoip] raw rows: ${RAW}"

echo "[geoip] converting ranges to CIDR..."
"${CH[@]}" -n <<'SQL'
INSERT INTO geoip
SELECT
    concat(
        toString(toIPv4(bitAnd(bitNot(toUInt32(pow(2, unmatched) - 1)), toUInt32(ip_range_start)))),
        '/',
        toString(toUInt8(32 - unmatched))
    ) AS cidr,
    latitude,
    longitude,
    ifNull(country_code, '') AS country_code,
    ifNull(city, '') AS city
FROM
(
    SELECT
        ip_range_start,
        latitude,
        longitude,
        country_code,
        city,
        if(
            bitXor(toUInt32(ip_range_start), toUInt32(ip_range_end)) != 0,
            ceil(log2(bitXor(toUInt32(ip_range_start), toUInt32(ip_range_end)) + 1)),
            0
        ) AS unmatched
    FROM geoip_raw
    WHERE latitude != 0 OR longitude != 0
);
SQL

ROWS=$("${CH[@]}" -q "SELECT count() FROM geoip")
echo "[geoip] cidr rows: ${ROWS}"

echo "[geoip] creating dictionary..."
"${CH[@]}" -n <<'SQL'
DROP DICTIONARY IF EXISTS geoip_trie;

CREATE DICTIONARY geoip_trie
(
    cidr String,
    latitude Float64,
    longitude Float64,
    country_code String,
    city String
)
PRIMARY KEY cidr
SOURCE(CLICKHOUSE(
    HOST 'localhost'
    PORT 9000
    USER 'default'
    PASSWORD 'flow'
    TABLE 'geoip'
    DB 'default'
))
LAYOUT(IP_TRIE)
LIFETIME(3600);
SQL

echo "[geoip] test lookup 8.8.8.8:"
"${CH[@]}" -q "SELECT dictGet('geoip_trie', ('latitude','longitude','country_code','city'), toIPv4('8.8.8.8'))"

echo "[geoip] done. Attribution: IP Geolocation by DB-IP https://db-ip.com (CC BY 4.0)"
