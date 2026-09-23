# ct-signal

Static website for **signal.catalant.com** — "The Signal", a recurring Catalant publication.
Single self-contained HTML page per issue, served by hardened nginx on GKE.

Ticket: [CT-60660](https://gocatalant.atlassian.net/browse/CT-60660)

## What is here

| Path | Purpose |
| --- | --- |
| `src/` | Web root. Everything here is served. Add pages here. |
| `src/index.html` | Current issue |
| `nginx/default.conf` | Server config, routing, cache policy |
| `scripts/gen_csp.py` | Computes CSP script hashes at image build time |
| `scripts/serve_test.sh` | Serve + security-header assertions, run in CI |
| `scripts/manifest_check.py` | Offline manifest parse and shape check |
| `Dockerfile` | 2 stages: CSP generation, then nginx runtime |
| `k8s/` | namespace, deployment, service, ingress, frontendconfig, backendconfig, networkpolicy |
| `cloudbuild.yaml` | master push → build, push, deploy |
| `cloudbuild.pr.yaml` | pull request → build, serve tests, manifest check |
| `Makefile` | Local dev targets |

## Run it locally

```bash
make run
```

Serves on http://localhost:8088. Override with `make run PORT=9000`.

| Target | Does |
| --- | --- |
| `make run` | Build + run detached, hardened the same way as in-cluster |
| `make headers` | Dump response headers |
| `make logs` | Follow nginx logs |
| `make down` | Stop and remove the container |
| `make build` | Build the image only |
| `make lint` | `nginx -t` inside the image |
| `make test` | Full serve + security-header test suite |
| `make csp` | Print the generated CSP / header snippet |
| `make validate` | Parse and shape-check the manifests in `k8s/` |
| `make clean` | Remove container and image |

## Publish a new issue

1. Add or replace the HTML in `src/`
2. `make run`, confirm the page renders at http://localhost:8088
3. Branch, commit, open a PR against `master`
4. Get 1 approval; Cloud Build check must pass
5. Merge to `master` → Cloud Build builds and rolls out

`scripts/gen_csp.py` rescans every `.html` under `src/` on each build, so inline `<script>`
hashes stay current. No manual CSP edit is needed when content changes.

## Content rules

| Rule | Consequence if broken |
| --- | --- |
| No external `<script src=...>` | Build fails until its origin is added to `script-src` in `scripts/gen_csp.py` |
| New outbound `fetch()` host | Blocked at runtime until added to `connect-src` in `scripts/gen_csp.py` |
| `.html` served `no-cache`; other assets `max-age=86400` | — |
| Only `GET` / `HEAD` | Anything else returns 405 |

## Deploy

| | |
| --- | --- |
| Deploy trigger | push to `master` only |
| Merge gate | 1 approving review + passing Cloud Build check |
| Build project | `catalant-jenkins` |
| Image | `us-docker.pkg.dev/catalant-jenkins/catalant/ct-signal` |
| Deployed by | image digest, not tag |
| Cluster | `catalant-prod-cluster` / `us-east1-d` / project `catalant-prod` |
| Namespace | `catalant-signal` |
| Static IP | `signal-catalant-ip` = `136.69.15.94` (global, `catalant-prod`) |
| DNS | zone `catalant-zone`, project `catalant-162206` |

## Reader feedback

The page collects name, two question answers with comments, and an account note.

| | |
| --- | --- |
| Destination | Google Form `1FAIpQLSfQ39KgltPssRl2mMlCOIFm4fhAUzrtn89D6nfW-xP2Q52UEw` |
| Recipient | Amanda Ewing (`aewing@gocatalant.com`) — receipt confirmed |
| Requires | `connect-src https://docs.google.com` in the CSP |
| Submit | Works |
| Draft autosave | Does not work off the Claude artifact host; `window.claude` is absent |
| Delivery confirmation | None — the POST is `mode: 'no-cors'`, so the response is opaque |

## Certificate

| | |
| --- | --- |
| Secret | `catalant-com-tls` |
| SANs | `*.catalant.com`, `catalant.com` |
| Issuer | DigiCert |
| Expires | 2027-02-27 |
| Source namespace | `catalant-prod` |
| Served from namespace | `catalant-signal` |
| Replicated by | kubed v0.13.2 (`kube-system`), scoped to the `catalant-com-tls` namespace label |

## Security posture

- CSP `default-src 'none'`; `script-src` sha256 hashes only, no `unsafe-inline` for scripts
- HSTS 2y + `includeSubDomains` + `preload`; `X-Frame-Options: DENY`; `frame-ancestors 'none'`; nosniff; COOP/CORP `same-origin`; `Permissions-Policy` denies all features
- Security headers present on error responses, not just 200s
- `server_tokens off` — `Server: nginx`, no version
- Non-existent paths, dotfiles and traversal attempts do not serve content
- Base image's stock `50x.html` removed; only `src/` is served
- Base images pinned by digest, pulled via the org Docker Hub proxy
- Container: non-root uid 101, read-only root filesystem, all capabilities dropped, no privilege escalation, `seccompProfile: RuntimeDefault`
- Writable paths are memory-backed tmpfs; content is `444`, owned by root, not writable by nginx
- No service-account token mounted
- Namespace enforces Pod Security `restricted`
- NetworkPolicy: default-deny ingress and egress; only GCLB ranges `35.191.0.0/16` and `130.211.0.0/22` reach `:8080`
- TLS 1.2 minimum via `prod-ssl-policy` (RESTRICTED); HTTP 301s to HTTPS

### Accepted gaps

| Gap | Reason |
| --- | --- |
| `style-src 'unsafe-inline'` | Page uses 10 `style="..."` attributes. CSP3 ignores `'unsafe-inline'` once a hash is present, and Firefox does not implement `style-src-attr`. Removing the attributes allows tightening to hashes. |
| `connect-src https://docs.google.com` | Required for reader feedback. Confirmed wanted. |
| No `.well-known/security.txt` | Needs a security contact. nginx already serves `src/.well-known/`. |

