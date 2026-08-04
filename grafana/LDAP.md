# Grafana LDAP (direct)

LDAP is enabled in Compose (`GF_AUTH_LDAP_ENABLED=true`).  
You only need to edit the bind/server details.

## On 10.0.20.201

```bash
cd /home/al/goflow2-stack
sudo nano grafana/ldap.toml          # fill host, bind_dn, bind_password, search_base_dns, groups
sudo docker compose up -d grafana    # recreate to reload config
sudo docker compose logs -f --tail=50 grafana
```

Local `admin` still works after LDAP is on (until you disable login form).

## Fields to change in `grafana/ldap.toml`

| Key | What to put |
|-----|-------------|
| `host` / `port` | DC hostname or IP; 389 or 636 |
| `use_ssl` | `true` for LDAPS (port 636) |
| `bind_dn` / `bind_password` | Read-only service account |
| `search_base_dns` | e.g. `["DC=eit,DC=al,DC=com"]` |
| `search_filter` | AD: `(sAMAccountName=%s)` |
| `group_mappings` | Map AD groups → Admin / Editor / Viewer |

Template without secrets: `grafana/ldap.toml.example`.

## Test from the Grafana host

```bash
# reachability
nc -vz <dc-host> 389
# or
nc -vz <dc-host> 636
```

Login at http://10.0.20.201:3030 with a domain user (usually `sAMAccountName`, not `DOMAIN\user`).

## Failures

```bash
cd /home/al/goflow2-stack
sudo docker compose logs --tail=100 grafana | grep -i ldap
```

Common issues: wrong Base DN, bind account locked, firewall, group DN mismatch (user logs in but gets wrong role / denied).
