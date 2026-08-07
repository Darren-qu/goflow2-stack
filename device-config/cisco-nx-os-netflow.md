# Cisco NX-OS — NetFlow → goflow2-stack

Collector: `<COLLECTOR_IP>` **UDP 2055**.

Feature and syntax differ by NX-OS train (Nexus 9K/7K). Confirm with `feature ?` / `ip flow ?`.

## Example

```text
feature netflow

flow exporter GF_EXPORTER
  destination <COLLECTOR_IP> use-vrf management
  transport udp 2055
  source mgmt0
  version 9
  template data timeout 60

flow record GF_RECORD
  match ipv4 source address
  match ipv4 destination address
  match ip protocol
  match transport source-port
  match transport destination-port
  collect counter bytes
  collect counter packets
  collect timestamp sys-uptime first
  collect timestamp sys-uptime last

flow monitor GF_MONITOR
  record GF_RECORD
  exporter GF_EXPORTER

sampler GF_SAMPLER
  mode sample-rate 1000

interface Ethernet1/1
  ip flow monitor GF_MONITOR input sampler GF_SAMPLER
  ip flow monitor GF_MONITOR output sampler GF_SAMPLER
```

## Notes

- Sample rate **1000** ≈ 1:1000; increase on busy TOR/core ports.
- If mgmt VRF cannot reach the collector, use a data VRF / loopback and matching `use-vrf`.
- Template timeout **60s** helps GoFlow2 see v9 templates quickly after reload.

## Verify

```text
show flow exporter
show flow monitor GF_MONITOR statistics
```

Collector: `sudo tcpdump -ni any udp port 2055 -c 20`
