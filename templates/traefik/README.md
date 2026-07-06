# Traefik (LAN-only TLS)

Terminates HTTPS for pv-stack UIs with REAL Let's Encrypt certificates
obtained via DNS-01 (Cloudflare API) — nothing is exposed publicly: the
hostnames resolve to private LAN IPs.

Runtime state lives in `/docker-storage/pv-stack/traefik/`:
- `config/traefik.yml` — static config (entrypoints, ACME resolver)
- `config/dynamic/*.yml` — one file per routed hostname (hot-reloaded)
- `cf.env` — `CF_DNS_API_TOKEN=<Zone->DNS->Edit token for the zone>` (chmod 600, NOT in git)
- `acme/acme.json` — issued certificates (chmod 600, NOT in git)

The gateway behind it must whitelist Traefik's static IP (172.18.0.250) in
`ui.trusted_proxies`, otherwise lockout/audit/allowlist see the proxy IP.

Adding another UI = one more file in `config/dynamic/` + a DNS entry.
