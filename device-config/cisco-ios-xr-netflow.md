# Cisco IOS-XR — NetFlow → goflow2-stack

Collector: `<COLLECTOR_IP>` **UDP 2055**.

Example for a typical XR monitor map. Adjust sampler, map, and interface names for your platform (ASR9K / NCS / etc.).

## Flow monitor (v9)

```text
flow exporter-map GF_EXPORTER
 version v9
 !
 destination <COLLECTOR_IP>
 transport udp 2055
 source Loopback0
!

flow monitor-map GF_MONITOR
 record ipv4
 exporter GF_EXPORTER
 cache entries 65535
 cache timeout active 60
 cache timeout inactive 15
!

sampler-map GF_SAMPLER
 random 1 out-of 1000
!

interface GigabitEthernet0/0/0/1
 flow ipv4 monitor GF_MONITOR sampler GF_SAMPLER ingress
 flow ipv4 monitor GF_MONITOR sampler GF_SAMPLER egress
!
commit
```

IPFIX variant: set `version ipfix` under the exporter-map (same UDP 2055).

## Defaults to prefer

| Setting | Suggestion |
|---------|------------|
| Sampler | `1 out-of 1000` (raise on hotter links) |
| Active timeout | 60s |
| Template | XR refreshes with the monitor; if no data, check exporter reachable and ACL |

## Verify

```text
show flow exporter GF_EXPORTER
show flow monitor GF_MONITOR cache
```

On collector: `sudo tcpdump -ni any udp port 2055 -c 20`
