TRUNCATE TABLE IF EXISTS geoip;

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

SELECT dictGet('geoip_trie', ('latitude','longitude','country_code','city'), toIPv4('8.8.8.8'));
SELECT count() FROM geoip;
