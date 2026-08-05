#!/bin/bash
# Create / refresh well-known TCP/UDP port → service name dictionary.
# Safe to re-run on an existing ClickHouse volume.
set -euo pipefail

clickhouse-client --password flow -n <<-EOSQL
CREATE DATABASE IF NOT EXISTS dictionaries;

CREATE DICTIONARY IF NOT EXISTS dictionaries.services
(
    port UInt16,
    name String,
    category String
)
PRIMARY KEY port
LAYOUT(FLAT())
SOURCE(FILE(path '/var/lib/clickhouse/user_files/services.csv' format 'CSVWithNames'))
LIFETIME(3600);

SYSTEM RELOAD DICTIONARY dictionaries.services;
EOSQL

echo "[services] dictionary ready. sample:"
clickhouse-client --password flow -q "SELECT dictGetString('dictionaries.services', 'name', toUInt64(443)), dictGetString('dictionaries.services', 'category', toUInt64(443))"
