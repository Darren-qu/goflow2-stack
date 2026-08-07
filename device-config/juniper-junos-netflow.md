# Juniper Junos — sampling / J-Flow → goflow2-stack

Collector: `<COLLECTOR_IP>` **UDP 2055**.

Modern Junos often uses **sampling** with an inet flow export (family may be called jflow / ipfix depending on platform). Below is a common **sampling + flow server** pattern; confirm against your Junos version (`show chassis hardware`, `help`).

## Example (sampling to NetFlow v9-style export)

```text
forwarding-options {
    sampling {
        input {
            rate 1000;
            run-length 0;
        }
        family inet {
            output {
                flow-server <COLLECTOR_IP> {
                    port 2055;
                    version9 {
                        template {
                            ipv4;
                        }
                    }
                    source-address <EXPORT_SOURCE_IP>;
                }
                inline-jflow {
                    source-address <EXPORT_SOURCE_IP>;
                }
            }
        }
    }
}

interfaces {
    ge-0/0/1 {
        unit 0 {
            family inet {
                sampling {
                    input;
                    output;
                }
            }
        }
    }
}
```

Apply / commit per your change workflow (`commit check`, `commit`).

## Notes

| Setting | Suggestion |
|---------|------------|
| `rate 1000` | 1:1000 starting point |
| Template | Prefer version9/IPFIX so GoFlow2 can decode consistently |
| Inline vs PIC | Some platforms need `inline-jflow` or a services PIC — follow hardware docs |

## Verify

```text
show forwarding-options sampling
show services accounting flow inline-jflow
```

Collector: `sudo tcpdump -ni any udp port 2055 -c 20`
