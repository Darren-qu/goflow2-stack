# Arista EOS — sFlow → goflow2-stack

Collector: `<COLLECTOR_IP>` **UDP 6343** (sFlow).

```text
sflow running
sflow destination <COLLECTOR_IP> 6343
sflow source-interface Management1
sflow polling-interval 30
sflow sample 1000
!
interface Ethernet1
  sflow enable
!
```

## Notes

| Setting | Suggestion |
|---------|------------|
| `sflow sample` | Start at **1000** (1:1000); raise on busy spines |
| Polling | 20–60s is typical |
| Source interface | Reachable toward the collector |

Enable sFlow only on interfaces you care about.

## Verify

```text
show sflow
show sflow interfaces
```

Collector:

```bash
sudo ss -ulnp | grep 6343
sudo tcpdump -ni any udp port 6343 -c 20
```
