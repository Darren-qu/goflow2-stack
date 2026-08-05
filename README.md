# GoFlow2 + Kafka + ClickHouse + Grafana

开源流量分析栈（基于 [netsampler/goflow2](https://github.com/netsampler/goflow2) 官方 `compose/kcg`，改为预构建镜像、可独立部署）。

```text
网络设备 (NetFlow/IPFIX :2055, sFlow :6343)
        │
        ▼
     GoFlow2  ──protobuf──►  Kafka  ──►  ClickHouse
        │                                      │
   metrics:8080                         Grafana :3030
        │
   Prometheus :9090
```

> 若你更想要「开箱即用的流量分析 UI」，优先考虑 **Akvorado**。  
> 本栈适合：要自己控采集/存储、和现有 Grafana 体系集成。

## 一键部署（推荐）

仓库托管在内网 Gitea：`http://10.0.20.22:3000/netadmin/goflow2-stack`  
（Git SSH：`ssh://git@10.0.20.22:2222/netadmin/goflow2-stack.git`）

目标机执行：

```bash
# 已装 Docker Compose v2 + 本机 SSH 能访问 Gitea
curl -fsSL http://10.0.20.22:3000/netadmin/goflow2-stack/raw/branch/main/install.sh | bash

# 同时装 Docker（Debian/Ubuntu）
WITH_DOCKER=1 curl -fsSL http://10.0.20.22:3000/netadmin/goflow2-stack/raw/branch/main/install.sh | bash

# 顺带导入 GeoIP（地图看板，较慢）
WITH_GEOIP=1 curl -fsSL http://10.0.20.22:3000/netadmin/goflow2-stack/raw/branch/main/install.sh | bash
```

等价手动方式：

```bash
git clone ssh://git@10.0.20.22:2222/netadmin/goflow2-stack.git
cd goflow2-stack
./deploy.sh            # 拉镜像并启动
./deploy.sh --geoip    # 可选：导入地图 GeoIP
```

默认安装目录：`$HOME/goflow2-stack`（可用 `INSTALL_DIR=/opt/goflow2-stack` 覆盖）。

> 主机需能拉 Docker 镜像，且 **UDP 端口转发可用**（部分 Colima 环境收不到 UDP）。

首次启动后等 ClickHouse 跑完 `clickhouse/create.sh`（建表/物化视图），大约 30–60 秒。

## 端口

| 端口 | 用途 |
|------|------|
| **UDP 2055** | NetFlow v5/v9 / IPFIX |
| **UDP 6343** | sFlow |
| **3030** | Grafana（避开 ntopng 默认 3000） |
| 8123 | ClickHouse HTTP |
| 9000 | ClickHouse native |
| 8080 | GoFlow2 metrics |
| 9090 | Prometheus |

### 访问

- Grafana: `http://<主机IP>:3030`  
  - 用户 / 密码：`admin` / `admin`（请立刻改掉）  
  - LDAP：已启用骨架，编辑 `grafana/ldap.toml` 后 `docker compose up -d grafana`（见 [grafana/LDAP.md](grafana/LDAP.md)）
  - 预置看板：
    - **Traffic Overview**（主大屏）：`/d/flow-traffic-overview`  
      一眼看概况：总量 / 趋势 / 协议 / Top 源·目的·服务（无筛选、无 Sankey、无地图）
    - **Traffic Sankey**（分析流向）：`/d/flow-sankey`（含维度与过滤变量）
    - **Traffic Geo Map**（公网地理）：`/d/flow-geo-map`
    - **IP Flow Lookup**（单 IP 查询）：`/d/flow-ip-lookup`  
      用端口推断应用（HTTPS/DNS/SSH…）+ 对端 GeoIP，尽量回答「访问了什么」。  
      **说明：NetFlow 本身没有域名/URL**；若要真实域名需 DNS/SNI 旁路采集。
    - `viz-ch` / `perfs`：GoFlow2 官方示例

Sankey 过滤变量（仅 Sankey 页）：

| Variable | Usage |
|----------|--------|
| Dimension | SrcIP→DstIP / Exporter→DstIP / … |
| Top N | Nodes kept on each side; rest → Other |
| Exporter / Protocol / Dst Port | Dropdown; All = no filter |
| Src/Dst CIDR | e.g. `10.0.0.0/8`; empty = no filter |

> Current flows have `src_as`/`dst_as` = 0 (no BGP/BMP), so no AS dimension.

GeoIP 字典初始化（已在 10.0.20.201 做过一次；重建时）：

```bash
# 下载 dbip-city-ipv4.csv.gz → 解压 → 导入 ClickHouse → build_geoip_trie.sql
# 详见 clickhouse/setup_geoip.sh 与 clickhouse/build_geoip_trie.sql
```

地图数据来源：[DB-IP Lite](https://db-ip.com)（CC BY 4.0），经 [sapics/ip-location-db](https://github.com/sapics/ip-location-db) 分发。
- ClickHouse: `default` / `flow`

### 设备侧导出

把 exporter 指向本机 IP：

- NetFlow / NetStream / IPFIX → `<本机IP>:2055`
- sFlow → `<本机IP>:6343`

华为 NetStream 示例见 `elk-netflow-setup/docs/huawei-firewall-netstream.md`（把目标改成本栈 IP:2055）。

### 验证有没有流进来

```bash
# GoFlow2 是否在听
docker compose logs -f --tail=50 goflow2

# ClickHouse 行数
docker compose exec db clickhouse-client --password flow -q \
  'SELECT count() FROM flows_raw'

# 本机抓包
sudo tcpdump -ni any udp port 2055 -c 20
sudo tcpdump -ni any udp port 6343 -c 20
```

若设备未带采样率，Grafana 里按 `bytes * sampling_rate` 算的流量可能为 0 或异常，需在看板 SQL 里去掉采样倍率或在设备上配置采样。

## 常用命令

```bash
cd ~/goflow2-stack   # 或你的 INSTALL_DIR
./deploy.sh --no-pull          # 仅按当前 compose 重启/应用
docker compose logs -f db
docker compose restart goflow2
docker compose down            # 停服务（保留 volume 数据）
docker compose down -v         # 停并清空 ClickHouse/Grafana 数据
```

## 目录说明

| 路径 | 说明 |
|------|------|
| `install.sh` | 从 GitHub clone/更新后调用 `deploy.sh` |
| `deploy.sh` | 一键 `pull` + `compose up`（可选 `--geoip`） |
| `docker-compose.yml` | 编排 |
| `clickhouse/create.sh` | 建 Kafka 引擎表、`flows_raw`、5 分钟聚合 |
| `clickhouse/flow.proto` | Protobuf schema（与 GoFlow2 `-format=bin` 对应） |
| `grafana/dashboards/` | 预置看板 JSON |
| `grafana/ldap.toml.example` | LDAP 模板（本地复制为 `ldap.toml`，勿提交密码） |
| `prometheus/` | 刮取 GoFlow2 metrics |

## 资源建议

- 试用 / 小流量：2–4 CPU，8 GB RAM，SSD ≥ 40 GB  
- 生产高流量：加大 ClickHouse 磁盘；Kafka/CH 不要和业务盘混用；按需调采样

## 与现有系统共存

- 与 **ntopng** 同机：本栈 Grafana 已改到 **3030**；UDP 2055/6343 只能有一个进程占用。  
- 与 **ELK Logstash** 同机：不要同时占 2055；可改 GoFlow2 监听端口或让设备双导出到不同 IP。  
- 与 **Akvorado** 二选一即可，不必叠两套 ClickHouse 流分析。
