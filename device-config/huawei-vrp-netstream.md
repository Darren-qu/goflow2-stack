# Huawei VRP / USG — NetStream → goflow2-stack

Collector: **GoFlow2** on `<COLLECTOR_IP>` **UDP 2055** (NetFlow v5/v9 / IPFIX).

Huawei usually calls this **NetStream** (NetFlow-compatible) or **IPFIX**. USG6000 / USG9500 / HiSecEngine / VRP trains differ slightly — treat the blocks below as common patterns and confirm with `ip netstream ?` on your box.

## Plan

| Item | Value |
|------|--------|
| Collector | `<COLLECTOR_IP>` |
| Port | **UDP 2055** |
| Version | Prefer **9** or **IPFIX (10)**; use **5** only to prove the path |
| Sampling | e.g. 1:1000 – 1:10000 on busy interfaces |
| Interfaces | Egress / core / zone borders — not every interface |

```text
ping <COLLECTOR_IP>
```

## Minimal config (common USG / VRP)

```text
system-view

ip netstream export host <COLLECTOR_IP> 2055
ip netstream export version 9
ip netstream export source <FW_EXPORT_SOURCE_IP>

ip netstream timeout active 60
ip netstream timeout inactive 30

ip netstream sampler fix-packets 1000 inbound
ip netstream sampler fix-packets 1000 outbound

interface GigabitEthernet0/0/1
 ip netstream inbound
 ip netstream outbound
 quit

quit
save
```

Some trains use:

```text
ip netstream export host ip <COLLECTOR_IP> port 2055
```

or on the interface:

```text
 netstream inbound
 netstream outbound
```

## IPFIX (version 10)

```text
system-view
ip netstream export version 10
ip netstream export host <COLLECTOR_IP> 2055
# enable inbound/outbound on interfaces as above
```

GoFlow2 accepts IPFIX on the same UDP **2055** listener.

## NetFlow v9 templates (important)

If `tcpdump` shows UDP to 2055 but ClickHouse stays empty, v9 may be sending **Data** without **Template**. Force template refresh (syntax varies):

```text
system-view
ip netstream export version 9
ip netstream export template timeout-rate 1
ip netstream export template option timeout-rate 1
ip netstream export template refresh-rate packets 10
ip netstream export template refresh-rate seconds 30
quit
save
```

Quick path test with v5 (no templates), then switch back to v9 + refresh:

```text
ip netstream export version 5
```

## Verify on the firewall

```text
display ip netstream cache
display ip netstream export
display ip netstream statistics
```

Export counters should increase; destination must be `<COLLECTOR_IP>:2055`.

## Verify on the collector

```bash
sudo ss -ulnp | grep 2055
sudo tcpdump -ni any udp port 2055 -c 20
docker compose logs -f --tail=50 goflow2
docker compose exec db clickhouse-client --password "${CLICKHOUSE_PASSWORD:-flow}" -q \
  'SELECT count() FROM flows_raw'
```

Open Grafana → Traffic Overview (`:3030`).

## Security policy

Allow the firewall’s own export traffic if it is policy-checked:

- Src: export source / egress address  
- Dst: `<COLLECTOR_IP>`  
- Proto: UDP 2055  

Also allow inbound UDP 2055 on the collector host firewall.

## Checklist

- [ ] `export host <COLLECTOR_IP> 2055`
- [ ] Version 5/9/10 matches what you intend
- [ ] Interfaces have inbound/outbound NetStream
- [ ] Sampling is not 1:1 on busy links
- [ ] Policy allows UDP 2055
- [ ] `tcpdump` sees packets
- [ ] Grafana / `flows_raw` count increases
