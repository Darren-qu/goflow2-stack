# ClickHouse cluster sketch (advanced)

The default `docker-compose.yml` runs **one** ClickHouse node. That is enough for many enterprise sites with sampling and a 30‑day raw TTL.

Use a cluster when you outgrow that box — not by default.

## When to consider clustering

| Signal | Action before cluster |
|--------|------------------------|
| Disk filling under 30d TTL | Lower `FLOWS_RAW_TTL_DAYS`, add disk, raise sampling |
| Sustained very high insert rate | See README capacity table; sample harder |
| Need HA if one host dies | Then plan Keeper + replicas |

Rough single-node comfort zone (SSD, 8–16 GB RAM, sampled enterprise flows): on the order of **a few thousand to ~10–20k flow records/sec**. Treat as a **ballpark**, not an SLA. Past that, shorten retention and/or split.

## What the example file is

[`docker-compose.override.cluster.yml.example`](../docker-compose.override.cluster.yml.example) only shows **service names** for:

- 1× ClickHouse Keeper (production usually 3)
- 2 shards × 2 replicas (`ch-s1r1` … `ch-s2r2`)
- Compose **`profiles: [cluster-example]`** so normal `docker compose up` never starts them

It does **not** ship full `config.xml` / `remote_servers` / ZooKeeper paths. You must add:

1. Keeper configuration  
2. Macros: `shard`, `replica`  
3. `<remote_servers>` cluster definition  
4. Table engines: `ReplicatedMergeTree` locally + `Distributed` (or replicated database) for queries  
5. How Kafka / GoFlow2 feed the cluster (often one ingest path writing to a Distributed table)

## Suggested next reads

- [ClickHouse replication](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replication)  
- [ClickHouse Keeper](https://clickhouse.com/docs/en/guides/sre/keeper/clickhouse-keeper)  

Keep Grafana pointing at a single HTTP endpoint (load balancer or Distributed node) so dashboards stay simple.
