# Grafana LDAP / Active Directory login

LDAP is enabled in Compose (`GF_AUTH_LDAP_ENABLED=true`). `deploy.sh` creates
`grafana/ldap.toml` from `grafana/ldap.toml.example` on first run; that file is
local and gitignored. Edit it, then reload Grafana:

```bash
cd ~/goflow2-stack                 # or your INSTALL_DIR
nano grafana/ldap.toml             # host, bind_dn, bind_password, search_base_dns, groups
docker compose up -d --force-recreate grafana
docker compose logs -f --tail=50 grafana
```

The local `admin` account keeps working after LDAP is on (until you disable the
login form).

## Choose the connection security

All three modes are supported; which one to use is your decision. On an
internal network plain LDAP works, but the user's password and the bind
password then cross the network unencrypted between Grafana and the directory
server. If the directory server offers TLS, prefer one of the encrypted modes.

| Mode | `port` | `use_ssl` | `start_tls` | Notes |
|------|--------|-----------|-------------|-------|
| Plain LDAP | 389 | `false` | `false` | No encryption. Simplest; acceptable only on a trusted network. |
| StartTLS | 389 | `true` | `true` | Upgrades the port-389 connection to TLS. |
| LDAPS | 636 | `true` | `false` | TLS from the first byte. |

For the encrypted modes Grafana must trust the certificate of the directory
server:

- Certificate from a public or already-trusted CA: nothing else to do.
- Internal CA: mount the CA certificate into the Grafana container and set
  `root_ca_cert = "/etc/grafana/ldap-ca.pem"` in `ldap.toml`.
- `ssl_skip_verify = true` encrypts without checking the certificate. It stops
  passive sniffing but not an active man-in-the-middle; use it for testing.

The same consideration applies to the Grafana UI itself: it is served over
plain HTTP on port 3030. To encrypt browser logins, put a TLS reverse proxy in
front of it or set `GF_SERVER_PROTOCOL=https` with a certificate.

## Fields to change in `grafana/ldap.toml`

| Key | What to put |
|-----|-------------|
| `host` / `port` | Directory server hostname or IP; port per the table above |
| `use_ssl` / `start_tls` | Per the table above |
| `bind_dn` / `bind_password` | Read-only service account |
| `search_base_dns` | e.g. `["DC=example,DC=com"]` |
| `search_filter` | AD: `(sAMAccountName=%s)` |
| `group_mappings` | Map directory groups to Admin / Editor / Viewer |

## Test from the Grafana host

```bash
nc -vz <ldap-host> 389      # plain LDAP / StartTLS
nc -vz <ldap-host> 636      # LDAPS
# show the certificate the server presents (LDAPS)
openssl s_client -connect <ldap-host>:636 -showcerts </dev/null | head -20
```

Log in at `http://<host-ip>:3030` with a directory user (usually
`sAMAccountName`, not `DOMAIN\user`).

## Failures

```bash
docker compose logs --tail=100 grafana | grep -i ldap
```

Common issues: wrong base DN, bind account locked, firewall, certificate not
trusted (encrypted modes), group DN mismatch (user logs in but gets the wrong
role or is denied).
