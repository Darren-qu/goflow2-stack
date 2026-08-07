# GoFlow2 + Kafka + ClickHouse + Grafana

开源流量分析栈：基于 [netsampler/goflow2](https://github.com/netsampler/goflow2) 官方 `compose/kcg`，改为预构建镜像、可独立部署。

```text
网络设备 (NetFlow/IPFIX :2055, sFlow :6343)
        │
        ▼
     GoFlow2 ──protobuf──► Kafka ──► ClickHouse
        │                                  │
   metrics :8080 (localhost)         Grafana :3030  ← 用户入口
        │
   Prometheus :9090 (localhost)
```

| 场景 | 建议 |
|------|------|
| 要开箱 UI、少维护 | 优先考虑 **Akvorado** |
| 要控采集/存储、接现有 Grafana / LDAP | 用本栈 |

当前参考部署：`10.0.20.201`（Grafana **13.1.2**，ClickHouse 已有流数据与 GeoIP）。

---

## 快速开始

仓库（内网 Gitea）：`http://10.0.20.22:3000/netadmin/goflow2-stack`  
Git SSH：`ssh://git@10.0.20.22:2222/netadmin/goflow2-stack.git`

```bash
# 已装 Docker Compose v2，且能访问 Gitea
curl -fsSL http://10.0.20.22:3000/netadmin/goflow2-stack/raw/branch/main/install.sh | bash

# 顺带装 Docker（Debian/Ubuntu）
WITH_DOCKER=1 curl -fsSL http://10.0.20.22:3000/netadmin/goflow2-stack/raw/branch/main/install.sh | bash

# 顺带导入 GeoIP（地图看板，较慢）
WITH_GEOIP=1 curl -fsSL http://10.0.20.22:3000/netadmin/goflow2-stack/raw/branch/main/install.sh | bash
```

手动：

```bash
git clone ssh://git@10.0.20.22:2222/netadmin/goflow2-stack.git
cd goflow2-stack
cp .env.example .env          # 改默认密码
./deploy.sh                   # pull + up
./deploy.sh --geoip           # 可选：地图 GeoIP
```

默认目录：`$HOME/goflow2-stack`（`INSTALL_DIR=...` 可覆盖）。  
首次启动等 ClickHouse 跑完 `clickhouse/create.sh`，约 30–60 秒。主机需能拉镜像，且 **UDP 可达**（部分 Colima 收不到 UDP）。

---

## 端口与安全

| 端口 | 绑定 | 用途 |
|------|------|------|
| **UDP 2055** | `0.0.0.0` | NetFlow v5/v9 / IPFIX |
| **UDP 6343** | `0.0.0.0` | sFlow |
| **3030** | `0.0.0.0` | Grafana UI（避开 ntopng `:3000`） |
| 8123 / 9000 | `127.0.0.1` | ClickHouse HTTP / native |
| 8080 | `127.0.0.1` | GoFlow2 metrics |
| 9090 | `127.0.0.1` | Prometheus |

Kafka **不**映射主机端口。

**默认收紧：**

- 管理口只绑 localhost；口令在 `.env`（gitignore，从 `.env.example` 复制）。
- Grafana 关匿名访问；LDAP 见 [grafana/LDAP.md](grafana/LDAP.md)。
- 主机防火墙仍应限制 **3030** 与 UDP **2055/6343** 来源网段。

> 已有 `ch_data` volume 时，改 `.env` 里 `CLICKHOUSE_PASSWORD` **不会**自动改库内密码（仅首次初始化生效）。

---

## Grafana 看板

入口：`http://<主机IP>:3030`（账号见 `.env` 的 `GRAFANA_ADMIN_*`，默认 `admin`/`admin`，请立刻改掉）。

| 看板 | UID / 路径 | 说明 |
|------|------------|------|
| **Traffic Overview** | `/d/flow-traffic-overview` | 总量、bps 趋势、L4/应用饼图、Top 源·目的·服务；Direction = All / East-West / North-South；**Top N** 默认 8（可改） |
| **IP Flow Lookup** | `/d/flow-ip-lookup` | 单 IP：Inbound/Outbound 趋势、应用推断、Flow summary；Role = Any / Outbound / Inbound |
| **Traffic Sankey** | `/d/flow-sankey` | 维度 + Exporter/协议/端口/CIDR 过滤；Top N / Detail rows 默认 8 |
| **Traffic Geo Map** | `/d/flow-geo-map` | 公网地理（初始**全球视角**）；Map IP = Destination / Source；Top N 默认 8 |
| `viz-ch` / `perfs` | 官方示例 | GoFlow2 自带 |

**单位约定：** 表格/Stat 总量用 **bytes**；趋势图用 **bps**（`sum(bytes)*8/$interval`）。

**应用名：** 优先 `dictionaries.services` / 特权端口；无法识别时显示 `port-NNNN`（不用原始回程 `dst_port` 当“服务”，避免临时端口噪声）。

Sankey 变量：

| 变量 | 作用 |
|------|------|
| Dimension | SrcIP→DstIP / Exporter→DstIP / … |
| Top N | 每侧保留节点数，其余 → Other |
| Exporter / Protocol / Dst Port | 下拉；All = 不过滤 |
| Src/Dst CIDR | 如 `10.0.0.0/8`；空 = 不过滤 |

> 当前流里 `src_as`/`dst_as` 多为 0（无 BGP/BMP），故无 AS 维度。

---

## 数据保留（日志 / 流量生命周期）

本栈把「流数据」分层存放，**ClickHouse 是唯一长期真相**；Kafka 只做短缓冲。

```text
设备 → GoFlow2 → Kafka（默认保留 48h）→ ClickHouse
                                      ├─ flows_raw   明细（默认 30 天 TTL）
                                      └─ flows_5m    5 分钟聚合（默认 180 天 TTL）
```

| 层 | 用途 | 默认保留 | 怎么清 |
|----|------|----------|--------|
| Kafka `flows` | 写入缓冲，防 ClickHouse 短暂抖动 | **48 小时** | broker `log.retention.hours` |
| `flows_raw` | IP Lookup / Top 表 / 明细排查 | **30 天** | MergeTree **TTL**（按 `date` 分区整段丢弃） |
| `flows_5m` | 较长趋势（若看板用到） | **180 天** | 同上 |
| GeoIP 字典表 | 地图坐标 | 长期保留 | 不自动删 |
| Grafana / Prometheus | UI 与自监控 | volume 内 | 不自动删流量数据 |

**为何这样分：**

- 明细行数涨得最快，30 天够日常排障与多数安全回溯；要更严合规可把 `.env` 改成 `FLOWS_RAW_TTL_DAYS=90`。
- 聚合便宜一个数量级，可留半年看趋势。
- `ttl_only_drop_parts=1`：整日分区过期后直接丢 part，比逐行删省 IO。

**配置（`.env`）：**

```bash
FLOWS_RAW_TTL_DAYS=30
FLOWS_5M_TTL_DAYS=180
KAFKA_LOG_RETENTION_HOURS=48
```

`./deploy.sh` 会在 ClickHouse 就绪后执行 `clickhouse/apply_retention.sh`（对已有表 `ALTER … MODIFY TTL`，可重复跑）。只改保留策略时：

```bash
# 改 .env 中 FLOWS_*_TTL_DAYS 后刷新 CH TTL
docker compose exec -e CLICKHOUSE_PASSWORD -e FLOWS_RAW_TTL_DAYS -e FLOWS_5M_TTL_DAYS \
  db bash /docker-entrypoint-initdb.d/apply_retention.sh

# 改 KAFKA_LOG_RETENTION_HOURS 后必须一起重建下游（否则 GoFlow2/CH 会断流）
docker compose up -d --force-recreate kafka goflow2 db
```

> **注意：** 单独 `force-recreate kafka` 后，GoFlow2 / ClickHouse Kafka 引擎仍连旧 broker，看板会出现「有历史、无最新」。务必同时 recreate **`goflow2` + `db`**。

**空间观察：**

```bash
docker compose exec db clickhouse-client --password "${CLICKHOUSE_PASSWORD:-flow}" -q "
SELECT table, formatReadableSize(sum(bytes_on_disk)) AS size, min(partition), max(partition)
FROM system.parts
WHERE active AND table IN ('flows_raw','flows_5m')
GROUP BY table"
```

过期分区在后台 merge 时删除，不是改 TTL 瞬间腾空；磁盘告警仍建议在主机监控里盯 Docker 数据盘。

---

## GeoIP

地图依赖 ClickHouse `geoip_trie`（[DB-IP Lite](https://db-ip.com)，CC BY 4.0，经 [sapics/ip-location-db](https://github.com/sapics/ip-location-db)）。

```bash
./deploy.sh --geoip
# 或：docker compose exec db bash /docker-entrypoint-initdb.d/setup_geoip.sh
```

详见 `clickhouse/setup_geoip.sh`。

---

## 设备导出与验流

- NetFlow / NetStream / IPFIX → `<本机IP>:2055`
- sFlow → `<本机IP>:6343`

华为 NetStream 可参考仓库外文档 `elk-netflow-setup/docs/huawei-firewall-netstream.md`（目标改成本栈 IP:2055）。

```bash
docker compose logs -f --tail=50 goflow2

docker compose exec db clickhouse-client --password "${CLICKHOUSE_PASSWORD:-flow}" -q \
  'SELECT count() FROM flows_raw'

sudo tcpdump -ni any udp port 2055 -c 20
sudo tcpdump -ni any udp port 6343 -c 20
```

若设备未带采样率，看板里 `bytes * sampling_rate` 可能异常，需改 SQL 或在设备上配采样。

---

## 运维

```bash
cd ~/goflow2-stack          # 或 INSTALL_DIR
./deploy.sh --no-pull       # 按当前 compose 应用/重启
docker compose logs -f db
docker compose restart goflow2
docker compose up -d --force-recreate grafana   # 改 ldap.toml / 看板后常用
# 改 Kafka 相关配置后（保留时长等）— 三者一起重建，避免断流：
docker compose up -d --force-recreate kafka goflow2 db
docker compose down         # 停服务，保留 volume
docker compose down -v      # 清空 ClickHouse / Grafana 数据
```

| 路径 | 说明 |
|------|------|
| `install.sh` | clone/更新后调 `deploy.sh` |
| `deploy.sh` | `pull` + `up`（`--geoip` / `--no-pull`） |
| `docker-compose.yml` | 编排（Grafana 13.1.2） |
| `.env.example` | 口令与 Grafana 端口模板 |
| `clickhouse/create.sh` | Kafka 引擎表、`flows_raw`、5 分钟聚合（含默认 TTL） |
| `clickhouse/apply_retention.sh` | 对已有表应用/刷新 TTL（deploy 自动跑） |
| `clickhouse/services.csv` | 知名端口 → 应用名 |
| `grafana/dashboards/` | 预置看板 |
| `grafana/ldap.toml.example` | LDAP 模板（复制为 `ldap.toml`，勿提交） |
| `prometheus/` | 刮取 GoFlow2 metrics |

**资源：** 试用 2–4 CPU / 8 GB / SSD ≥ 40 GB；生产加大 CH 盘，Kafka/CH 勿与业务盘混用。

**共存：**

- **ntopng** 同机：本栈用 **3030**；UDP 2055/6343 只能一家占用。
- **Logstash** 同机：勿抢 2055。
- **Akvorado**：二选一即可。
