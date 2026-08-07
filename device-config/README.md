# Device export templates

Point network devices at this stack’s collector:

| Protocol | Port | Service |
|----------|------|---------|
| NetFlow v5/v9 / IPFIX / Huawei NetStream | **UDP 2055** | GoFlow2 |
| sFlow | **UDP 6343** | GoFlow2 |

Replace `<COLLECTOR_IP>` with the host running `goflow2-stack` (the address exporters can reach).

## Checklist

1. Device can route/ping `<COLLECTOR_IP>`
2. Host firewall allows inbound UDP **2055** / **6343**
3. Paste a vendor snippet below; set sampling (do not leave 1:1 on busy links)
4. On the collector: `sudo tcpdump -ni any udp port 2055 -c 20`
5. Grafana Overview should show new points within ~1–2 minutes

## Sampling guidance

| Link busy-ness | Starting sample rate |
|----------------|----------------------|
| Lab / light | 1:100 – 1:1000 |
| Production edge | 1:1000 – 1:4096 |
| Very busy core | 1:4096 – 1:10000 |

Dashboards scale with `bytes * sampling_rate`. If the device sends `sampling_rate = 0`, totals will look wrong until you fix the device or SQL.

## Vendors

| File | Platform |
|------|----------|
| [huawei-vrp-netstream.md](huawei-vrp-netstream.md) | Huawei VRP / USG NetStream (NetFlow-compatible) |
| [cisco-ios-xr-netflow.md](cisco-ios-xr-netflow.md) | Cisco IOS-XR |
| [cisco-nx-os-netflow.md](cisco-nx-os-netflow.md) | Cisco NX-OS |
| [arista-eos-sflow.md](arista-eos-sflow.md) | Arista EOS sFlow |
| [juniper-junos-netflow.md](juniper-junos-netflow.md) | Juniper Junos (inline J-Flow / sampling) |

Commands vary by version. Use `?` / vendor docs when a keyword is missing. These are **common working snippets**, not a certified matrix for every train.
