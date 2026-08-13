# GoFlow2 + Kafka + ClickHouse + Grafana

Open-source flow analytics stack based on [netsampler/goflow2](https://github.com/netsampler/goflow2) `compose/kcg`, adapted for standalone deploy with prebuilt images.

```text
Network devices (NetFlow/IPFIX :2055, sFlow :6343)
        │
        ▼
     GoFlow2 ──protobuf──► Kafka ──► ClickHouse
        │                                  │
   metrics :8080 (localhost)         Grafana :3030  ← UI
        │
   Prometheus :9090 (localhost)
```

| Need | Suggestion |
|------|------------|
| Turnkey UI, less ops | Prefer **Akvorado** |
| Own the pipeline; plug into Grafana / LDAP | Use this stack |

Defaults: Grafana **13.1.2**; ClickHouse raw flows **30 days**, 5‑minute aggregates **180 days**.

---

## Quick start

Repo: [github.com/Darren-qu/goflow2-stack](https://github.com/Darren-qu/goflow2-stack)

```bash
# Docker Compose v2 already installed
curl -fsSL https://raw.githubusercontent.com/Darren-qu/goflow2-stack/main/install.sh | bash

# Also install Docker Engine (Debian/Ubuntu)
WITH_DOCKER=1 curl -fsSL https://raw.githubusercontent.com/Darren-qu/goflow2-stack/main/install.sh | bash

# Also load GeoIP (map dashboard; slower)
WITH_GEOIP=1 curl -fsSL https://raw.githubusercontent.com/Darren-qu/goflow2-stack/main/install.sh | bash

# Also load IP→ASN enrichment (Top AS / Sankey SrcAS→DstAS)
WITH_ASN=1 curl -fsSL https://raw.githubusercontent.com/Darren-qu/goflow2-stack/main/install.sh | bash
```

Manual:

```bash
git clone https://github.com/Darren-qu/goflow2-stack.git
cd goflow2-stack
cp .env.example .env          # change default passwords
./deploy.sh                   # pull + up
./deploy.sh --geoip           # optional GeoIP for maps
./deploy.sh --asn             # optional IP→ASN for src_as/dst_as
```

Install dir: `$HOME/goflow2-stack` (override with `INSTALL_DIR=...`).  
Wait ~30–60s for ClickHouse `clickhouse/create.sh` on first boot. The host must pull images and accept **UDP** (some Colima setups drop UDP).

---

## Ports & security

| Port | Bind | Purpose |
|------|------|---------|
| **UDP 2055** | `0.0.0.0` | NetFlow v5/v9 / IPFIX |
| **UDP 6343** | `0.0.0.0` | sFlow |
| **3030** | `0.0.0.0` | Grafana UI |

| 8123 / 9000 | `127.0.0.1` | ClickHouse HTTP / native |
| 8080 | `127.0.0.1` | GoFlow2 metrics |
| 9090 | `127.0.0.1` | Prometheus |

Kafka is **not** published on the host.

**Hardening defaults:**

- Management ports bind to localhost only; secrets live in `.env` (gitignored; copy from `.env.example`).
- Grafana anonymous auth is off; LDAP: [grafana/LDAP.md](grafana/LDAP.md).
- Still firewall **3030** and UDP **2055/6343** to trusted networks.

> Changing `CLICKHOUSE_PASSWORD` in `.env` does **not** update an existing `ch_data` volume (password is set only on first init).

---

## Grafana dashboards

UI: `http://<host-ip>:3030` (see `GRAFANA_ADMIN_*` in `.env`; default `admin`/`admin` — change immediately).

| Dashboard | Path | Notes |
|-----------|------|-------|
| **Traffic Overview** | `/d/flow-traffic-overview` | Totals, bps trend, L4/app pies, Top sources/destinations/services/**AS**; Direction = All / East-West / North-South; **Top N** default 8 |
| **IP Flow Lookup** | `/d/flow-ip-lookup` | Single IP: inbound/outbound, inferred apps, Flow summary; Role = Any / Outbound / Inbound |
| **Traffic Sankey** | `/d/flow-sankey` | Dimension + exporter/protocol/port/CIDR filters; Top N / Detail rows default 8 |
| **Traffic Geo Map** | `/d/flow-geo-map` | Public IP map (starts at **world** view); Map IP = Destination / Source; Top N default 8 |
| `viz-ch` / `perfs` | — | Upstream GoFlow2 samples |

**Units:** table/stat totals in **bytes**; trend panels in **bps** (`sum(bytes)*8/$interval`).

**Applications:** prefer `dictionaries.services` / privileged ports; unknown → `port-NNNN` (do not treat reverse-path ephemeral `dst_port` as the “service”).

Sankey variables:

| Variable | Role |
|----------|------|
| Dimension | SrcIP→DstIP / Exporter→DstIP / … / **SrcAS→DstAS** (needs `--asn`) |
| Top N | Nodes kept per side; rest → Other |
| Exporter / Protocol / Dst Port | Dropdown; All = no filter |
| Src/Dst CIDR | e.g. `10.0.0.0/8`; empty = no filter |

> Without `./deploy.sh --asn`, device-exported `src_as`/`dst_as` are often **0**, so AS panels/dimension stay empty.

---

## Data retention

ClickHouse is the **source of truth**; Kafka is only a short buffer.

```text
Devices → GoFlow2 → Kafka (48h default) → ClickHouse
                                      ├─ flows_raw   detail (30d TTL)
                                      └─ flows_5m    5‑min agg (180d TTL)
```

| Layer | Purpose | Default | Cleanup |
|-------|---------|---------|---------|
| Kafka `flows` | Write buffer | **48 hours** | `log.retention.hours` |
| `flows_raw` | Lookup / tops / forensics | **30 days** | MergeTree **TTL** (drop day partitions) |
| `flows_5m` | Longer trends | **180 days** | same |
| GeoIP tables | Map coordinates | Keep | not TTL’d with flows |
| ASN table / `asn_trie` | IP→AS enrichment | Keep | refresh via `./deploy.sh --asn` |
| Grafana / Prometheus | UI / self-metrics | volumes | not flow TTL |

**Why this split:** raw rows grow fastest (30d is enough for day‑to‑day ops; set `FLOWS_RAW_TTL_DAYS=90` if needed). Aggregates are cheap. `ttl_only_drop_parts=1` drops whole day parts when expired.

**`.env`:**

```bash
FLOWS_RAW_TTL_DAYS=30
FLOWS_5M_TTL_DAYS=180
KAFKA_LOG_RETENTION_HOURS=48
```

`./deploy.sh` runs `clickhouse/apply_retention.sh` after ClickHouse is up. To refresh policy only:

```bash
docker compose exec -e CLICKHOUSE_PASSWORD -e FLOWS_RAW_TTL_DAYS -e FLOWS_5M_TTL_DAYS \
  db bash /docker-entrypoint-initdb.d/apply_retention.sh

# After changing KAFKA_LOG_RETENTION_HOURS, recreate downstream together
docker compose up -d --force-recreate kafka goflow2 db
```

> **Warning:** recreating **kafka alone** leaves GoFlow2 / ClickHouse on the old broker — dashboards keep history but stop showing **new** data. Always recreate **`goflow2` + `db`** with kafka.

**Disk check:**

```bash
docker compose exec db clickhouse-client --password "${CLICKHOUSE_PASSWORD:-flow}" -q "
SELECT table, formatReadableSize(sum(bytes_on_disk)) AS size, min(partition), max(partition)
FROM system.parts
WHERE active AND table IN ('flows_raw','flows_5m')
GROUP BY table"
```

Expired parts are removed during background merges, not instantly when TTL changes. Monitor the Docker data disk on the host.

---

## GeoIP

Maps use ClickHouse `geoip_trie` ([DB-IP Lite](https://db-ip.com), CC BY 4.0, via [sapics/ip-location-db](https://github.com/sapics/ip-location-db)).

```bash
./deploy.sh --geoip
# or: docker compose exec db bash /docker-entrypoint-initdb.d/setup_geoip.sh
```

See `clickhouse/setup_geoip.sh`.

---

## ASN (IP → AS number)

When exporters omit BGP AS fields, load an IPv4 ASN dictionary and rewrite `flows_raw_view` so **new** rows get `src_as` / `dst_as` from IP lookup (device non-zero AS is kept).

```bash
./deploy.sh --asn
# or:
docker compose exec -e CLICKHOUSE_PASSWORD db bash /docker-entrypoint-initdb.d/setup_asn.sh
```

| Piece | Role |
|-------|------|
| `asn` table + `asn_trie` | IP_TRIE dict from [iptoasn](https://github.com/sapics/ip-location-db) IPv4 CIDR CSV |
| `flows_raw_view` | `if(src_as=0, dictGet(...), src_as)` (same for dst) |
| Grafana | Overview Top Source/Dest AS; Sankey **SrcAS → DstAS** |

### What runs automatically after `--asn`

| Automatic | Not automatic |
|-----------|----------------|
| **New** flows: `src_as` / `dst_as` filled when device sent `0` (IPv4 via `asn_trie`) | Historical rows already in `flows_raw` (not backfilled) |
| Enrichment stays on across restarts (MV + dictionary in ClickHouse volume) | IP→ASN **database refresh** — CSV is not downloaded on a schedule |
| Device-exported non-zero AS is kept as-is | Private / unrouted IPs (lookup miss → stay `0`) |

Re-run `./deploy.sh --asn` (or `setup_asn.sh`) every few months, or when AS ownership looks stale, to refresh the CSV. The dictionary `LIFETIME` only reloads the already-imported table; it does not fetch updates from the network.

See `clickhouse/setup_asn.sh`.

---

## Device export & verification

Point exporters at this host:

- NetFlow / NetStream / IPFIX → `<host-ip>:2055`
- sFlow → `<host-ip>:6343`

**Copy-paste device snippets:** see [`device-config/`](device-config/) (Huawei, Cisco IOS-XR / NX-OS, Arista sFlow, Juniper).

```bash
docker compose logs -f --tail=50 goflow2

docker compose exec db clickhouse-client --password "${CLICKHOUSE_PASSWORD:-flow}" -q \
  'SELECT count() FROM flows_raw'

sudo tcpdump -ni any udp port 2055 -c 20
sudo tcpdump -ni any udp port 6343 -c 20
```

If devices omit sampling rate, dashboard math using `bytes * sampling_rate` can look wrong — fix SQL or configure sampling on the device.

---

## Capacity planning

ClickHouse disk is driven by **flow record rate**, not by link Gbps. Sampling lowers fps; TTL bounds how many days you keep.

### Ballpark formula

Per raw row on disk (MergeTree overhead included), use roughly **200–300 bytes** (conservative). Then:

```text
disk_raw_bytes ≈ fps × 86400 × FLOWS_RAW_TTL_DAYS × bytes_per_row_on_disk
disk_5m_bytes  ≈ 0.05 … 0.15 × disk_raw_bytes   # often much smaller
disk_total     ≈ disk_raw + disk_5m + Kafka buffer + headroom (20–30%)
```

Example with **250 B/row**, **30-day** raw TTL (`fps × 86400 × 30 × 250`):

| Sustained fps | Raw ≈ 30d | Notes |
|---------------|-----------|--------|
| 1 000 | ~**18 GB** | Small site / heavy sampling |
| 5 000 | ~**90 GB** | Comfortable single SSD node |
| 20 000 | ~**360 GB** | Watch disk & query load |
| 50 000 | ~**900 GB** | Shorten TTL, sample more, or plan cluster |

Kafka at 48h is usually small next to ClickHouse if CH keeps up.

### Single-node vs cluster

| Mode | File | Role |
|------|------|------|
| **Default** | `docker-compose.yml` | One ClickHouse — fine for many enterprise deployments |
| **Sketch only** | `docker-compose.override.cluster.yml.example` | Keeper + 2×2 naming; see [`clickhouse/cluster/README.md`](clickhouse/cluster/README.md) |

**Before clustering:** raise sampling, add disk, or lower `FLOWS_RAW_TTL_DAYS`.  
**Consider clustering when:** sustained high fps (ballpark **tens of thousands** records/sec), disk stays **> ~70%**, or you need multi-host HA. The example is **not** wired into `install.sh`.

**Lab sizing reminder:** 2–4 CPU / 8 GB RAM / SSD ≥ 40 GB to start; keep Kafka/CH off busy application disks.

---

## Operations

```bash
cd ~/goflow2-stack          # or INSTALL_DIR
./deploy.sh --no-pull       # apply current compose
docker compose logs -f db
docker compose restart goflow2
docker compose up -d --force-recreate grafana   # after ldap.toml / dashboard edits
# After Kafka config changes — recreate all three to avoid a stall:
docker compose up -d --force-recreate kafka goflow2 db
docker compose down         # stop; keep volumes
docker compose down -v      # wipe ClickHouse / Grafana data
```

| Path | Role |
|------|------|
| `install.sh` | Clone/update then `deploy.sh` |
| `deploy.sh` | `pull` + `up` (`--geoip` / `--asn` / `--no-pull`) |
| `docker-compose.yml` | Stack (Grafana 13.1.2) |
| `.env.example` | Password / port template |
| `clickhouse/create.sh` | Kafka engine, `flows_raw`, 5m agg (+ default TTL) |
| `clickhouse/apply_retention.sh` | Apply/refresh TTL on existing tables |
| `clickhouse/setup_geoip.sh` | Optional DB-IP city → `geoip_trie` |
| `clickhouse/setup_asn.sh` | Optional IP→ASN → `asn_trie` + enrich MV |
| `clickhouse/services.csv` | Well-known port → app name |
| `grafana/dashboards/` | Provisioned dashboards |
| `grafana/ldap.toml.example` | LDAP template (copy to `ldap.toml`; do not commit secrets) |
| `device-config/` | Vendor NetFlow / sFlow snippets (Huawei, Cisco, Arista, Juniper) |
| `clickhouse/cluster/` | Notes for optional CH cluster sketch |
| `docker-compose.override.cluster.yml.example` | Non-default Keeper + 2×2 service skeleton |
| `prometheus/` | Scrapes GoFlow2 metrics |

**Coexistence:**

- **Logstash** (or another NetFlow collector) on the same host: do not share UDP 2055/6343.
- **Akvorado:** pick one stack; no need for two ClickHouse flow pipelines.
