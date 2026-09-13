# Developer Documentation — Inception

This document covers: environment setup from scratch, building and launching with the
Makefile and Docker Compose, container/volume management, data persistence, the design
and good practices used, the performance engineering that was done (with measurements),
the test suite, and a **defense preparation Q&A**.

---

## 1. Setting up the environment from scratch

### 1.1 Prerequisites

| Requirement | Notes |
|-------------|-------|
| Docker Engine ≥ 24 (25+ recommended) | `docker --version` — 25+ enables fast-startup healthchecks (`start-interval`) |
| Docker Compose v2 plugin | `docker compose version` |
| GNU Make ≥ 4 | `make --version` |
| `openssl` on the host | secrets + TLS certificate generation |
| `sudo` access | needed for `/etc/hosts` and data-dir cleanu |

### 1.2 Configuration files and secrets

Nothing is required up front: `make setup` (run automatically by `make up`) provisions
every missing piece and **never overwrites existing files**:

| File | Provisioning |
|------|--------------|
| `srcs/.env` | generated from `.env.example` with the login substituted |
| `secrets/db_password.txt` | random 24-byte password |
| `secrets/db_root_password.txt` | random 24-byte password |
| `secrets/credentials.txt` | two random lines (1 = WP admin pw, 2 = editor pw) |
| `secrets/ca.key` / `ca.crt` | local Root CA (10 years) |
| `secrets/server.key` / `server.crt` | server cert signed by the CA, SAN = `DOMAIN_NAME` |

To use custom passwords, create the three `.txt` files yourself before the first `make`.
To change the domain, edit `DOMAIN_NAME` in `srcs/.env` — the next `make up` re-issues
the server certificate automatically (its SAN is checked against the env file).

Key variables in `srcs/.env`:

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN_NAME` | Your 42 login domain | `dlesieur.42.fr` |
| `MYSQL_DATABASE` | WordPress DB name | `wordpress` |
| `MYSQL_USER` | DB application user | `wpuser` |
| `WP_ADMIN_USER` | WP admin login (**must not contain "admin"** — enforced at boot) | `superuser` |
| `WP_USER` | Regular WP user (editor role) | `editor` |

> **Security:** `secrets/` and `srcs/.env` are git-ignored. The CA private key never
> enters any container — nginx only receives the server cert + key as Docker secrets.

---

## 2. Building and launching (Makefile → Docker Compose)

```bash
make          # == make up : setup + build + start
```

The Makefile is the single orchestrator (subject requirement: it must build the images
through `docker-compose.yml`). `make up` does, in order:

1. `setup` — data dirs, `.env`, secrets, `/etc/hosts`, TLS material (§1.2).
2. `docker compose -f srcs/docker-compose.yml up -d --build` — builds the three images
   from their Dockerfiles (in parallel, with BuildKit) and starts the stack; the
   dependency chain is gated by real healthchecks (§6.4).

### All Makefile targets

| Command | Effect |
|---------|--------|
| `make up` | Provision + build & start (detached) |
| `make build` | Provision + build images only |
| `make down` / `stop` / `start` / `restart` | Container lifecycle |
| `make logs` / `make status` | Tail logs / `docker compose ps` |
| `make test` | Compliance suite: static + runtime checks |
| `make test-deep` | + crash-restart & down/up persistence checks |
| `make bench` / `make bench-full` | Build (+ boot) benchmarks — `bench-full` wipes project data |
| `make run_wp` | Guided health report: core checksums, users, themes, DB, OPcache |
| `make trust` | Install the local CA into system + Chrome/Firefox trust stores |
| `make clean` | Remove project containers + volumes + images + host data |
| `make fclean` | `clean` + `docker system prune -af --volumes` (machine-wide!) |
| `make re` | Full project rebuild — keeps Docker's build cache and other projects intact |
| `make test-lab` | Lab (web + api) checks; `LAB_ARGS=--deep` adds SIGTERM drain + late MariaDB |
| `make snapshot` / `make re-web` | Refresh the site's JSON snapshots from the running API / rebuild only `web` |
| `make lock` / `make npm-web NPM=…` / `make npm-api NPM=…` | npm inside `nodetool:inception`, never on the host |
| `make hellish-fetch` | Stage the static hellish release binary (checksum verified) |

---

## 3. Architecture

```text
            ┌──────────┐
Client ──►  | NGINX:443│   TLS 1.2/1.3 termination — the ONLY published port
            │  (nginx) │   serves static files directly from the shared volume (ro)
            └────┬─────┘
                 │ FastCGI :9000 (internal)
            ┌────▼──────────┐
            │ WordPress     │   php-fpm 8.4 + WP-CLI — no web server inside
            └────┬──────────┘
                 │ TCP :3306 (internal)
            ┌────▼──────────┐
            │ MariaDB 11.4  │   no web server inside
            └───────────────┘
```

- All three containers sit on the **`inception` bridge network**; they resolve each
  other by service name through Docker's embedded DNS. Only 443 is published.
- **Naming rules** (subject): each image is named after its service
  (`nginx:inception`, `wordpress:inception`, `mariadb:inception` — never `latest`),
  and the containers are named `nginx`, `wordpress`, `mariadb`.
- Each service is a self-contained build context:
  `srcs/requirements/<service>/{Dockerfile, conf/, tools/entrypoint.sh}`.
- nginx mounts the WordPress volume **read-only** and serves static assets itself;
  only `.php` requests are forwarded over FastCGI.

A fourth, **independent** container (bonus, §11.1) exists alongside these three: a
plain HTML/CSS/JS static site on its own port (8090), sharing no network dependency,
volume or secret with the mandatory trio above.

---

## 4. Managing containers and volumes

```bash
docker exec -it nginx     sh          # shell into a container
docker exec -it wordpress sh
docker exec -it mariadb   sh

# WP-CLI (any WordPress operation):
docker exec wordpress wp --allow-root --path=/var/www/html <command>

# Database shell (prompt reads the value of secrets/db_password.txt):
docker exec -it mariadb mariadb -u wpuser -p wordpress

# Volumes:
docker volume ls
docker volume inspect inception_db_data
docker volume inspect inception_wp_data
```

Wipe and rebuild from zero: `make clean && make` (or `make re`).

---

## 5. Data storage and persistence

| Docker volume | Host path | Contents |
|---------------|-----------|----------|
| `inception_db_data` | `/home/dlesieur/data/mariadb` | MariaDB data directory |
| `inception_wp_data` | `/home/dlesieur/data/wordpress` | WordPress core, themes, plugins, uploads |

Both are **named volumes** declared at the top level of `docker-compose.yml` with
`driver: local` and a `device` option pointing at the host directory. This satisfies
both subject rules at once: they are real named volumes (services never bind-mount a
host path), *and* their data lives inside `/home/login/data`. They survive
`make down` / `make up` cycles and reboots — `make test-deep` proves it by writing a
DB row and a file, cycling the stack, and reading them back.

Note: the MariaDB host directory ends up mode 750 owned by the container's `mysql`
uid — inspect its content via `docker exec mariadb ls /var/lib/mysql`, not the host path.

---

## 6. Entrypoint design & good practices

Every container starts through an entrypoint script with the same shape:

1. **Fail fast:** `set -eu` + `${VAR:?}` validation of required environment variables;
   secrets are read from `/run/secrets/*` and checked non-empty. The WordPress
   entrypoint additionally **rejects any admin username containing
   admin/Admin/administrator** (subject rule, enforced, not just documented).
2. **One-time initialisation behind an idempotence guard**, so restarts are instant
   and interrupted first boots self-heal:
   - **mariadb** — `mariadb-install-db` runs only if `/var/lib/mysql/mysql` is
     missing. The account/database bootstrap (root password, app DB, app user, grants)
     runs in **`mariadbd --bootstrap` mode**: the SQL is applied directly on stdin —
     no temporary server, no client, no authentication. It is guarded by a **marker
     file written only after full success**, so a boot killed mid-init simply retries.
     ⚠ Bootstrap mode has *skip-grant-tables* semantics: the SQL **starts with
     `FLUSH PRIVILEGES;`**, which loads the grant tables and makes
     `ALTER USER`/`GRANT` legal (without it: error 1290). Passwords are SQL-escaped
     and every statement is idempotent.
   - **wordpress** — the full core (themes included) is staged in the image at
     `/usr/src/wordpress`; first boot `cp -a`'s it into the volume, writes
     `wp-config.php` via heredoc (locally generated salts, PHP-escaped passwords),
     then `wp core install` + editor-user creation — guarded by `wp-config.php`
     existence.
   - **nginx** — installs the host-issued cert/key from secrets and renders the vhost
     template with `sed` that substitutes **only** the three `${...}` placeholders,
     leaving nginx runtime variables (`$uri`, …) untouched.
3. **Bounded wait loops only** — the WordPress→MariaDB wait probes with
   `php -r 'mysqli_connect(...)'` (no DB client installed) and gives up after 60s with
   a non-zero exit, letting the restart policy retry. Never `tail -f`, `bash`,
   `sleep infinity`, or `while true` (all prohibited by the subject — and grepped for
   by the test suite).
4. **`exec <daemon>` as the last line** — the daemon becomes **PID 1**, receives
   signals directly (clean `docker stop`), and no zombie shell stays in front of it.

**Consequence of the guards:** changing secrets or install parameters does **not**
propagate to an already-initialised stack (the DB and `wp-config.php` keep the values
from first boot). Re-apply with `make clean && make`.

**Multi-hostname `wp-config.php` (`WP_HOME`/`WP_SITEURL`):** by default WordPress
hard-redirects (301, `redirect_canonical()`) any request whose `Host` header doesn't
match its stored `siteurl`/`home` DB option — so a VM reachable only via a
NAT-forwarded `localhost:<port>` on the host (no `/etc/hosts` write access there,
§5b in `USER_DOC.md`) would 301 back to `dlesieur.42.fr`, which the host can't
resolve, and just fail. The generated `wp-config.php` instead defines `WP_HOME`/
`WP_SITEURL` dynamically from `$_SERVER['HTTP_HOST']`, checked against a hardcoded
whitelist (`DOMAIN_NAME`, `localhost`, `127.0.0.1` — the same three names the TLS
cert's SAN covers, §"Making it work" in the Makefile's `certs` target); anything
outside the whitelist falls back to the canonical domain rather than reflecting an
arbitrary client-supplied `Host` (Host-header spoofing/cache-poisoning would
otherwise be a risk). WP-CLI (no HTTP context, `$_SERVER['HTTP_HOST']` unset) always
falls back to the canonical domain too, so `wp option get siteurl` and `make run_wp`
keep reporting `https://dlesieur.42.fr` regardless. This is a standard pattern for a
single WordPress install reachable under more than one hostname, not a workaround —
and it's why nothing else (nginx `server_name`, the cert) needed to change: nginx has
only one `server {}` block on 443, so it already serves any Host on that port; only
WordPress itself was redirecting.

---

## 7. Security practices

- **Docker secrets, not environment variables, for every password** — mounted files
  with mode `0400` (root-only inside the container); `docker inspect <c>` shows no
  password-like variables (the test suite verifies this).
- **The CA private key never enters a container.** Certificates are issued on the host
  by `make setup`; nginx receives only the server cert + key. Since `make trust` makes
  browsers trust that CA, a container compromise must never be able to leak the CA key.
- **TLS 1.2/1.3 only**, declared explicitly in the vhost (`ssl_protocols`), ECDSA
  P-256 key, modern AEAD cipher list, `server_tokens off`.
- **Single entrypoint:** only nginx publishes a port, and only 443. WordPress and
  MariaDB are unreachable from the host.
- **Least privilege / least software:** php-fpm workers run as `nobody`;
  `wp-config.php` is `nobody:nobody` mode 640; `clear_env` stays at its safe default
  (env vars are not exposed to PHP); images contain no extra clients or tools
  (no wget package, no DB client in the WordPress image, >100MB of unused MariaDB
  binaries removed).
- **Injection-safe init:** passwords are escaped for their target context (SQL
  single-quotes, PHP single-quotes) before being embedded.
- **Git hygiene:** `secrets/` and `srcs/.env` are git-ignored; the test suite greps
  tracked files *and the full git history* for credential-looking content — the
  subject makes any credential in the repository an automatic failure.

---

## 8. Performance engineering

Every optimisation below is measurable with `make bench` / `make bench-full`.

### 8.1 Build-time

- **Minimal base, minimal packages** — `alpine:3.23` (penultimate stable, subject
  rule; pinned identically in all three Dockerfiles). The nginx image installs *only*
  `nginx`: certificates come from the host and template rendering uses `sed`, so
  neither `openssl` nor `gettext`/`envsubst` is needed. The WordPress image installs
  no `wget` (busybox handles HTTPS), no DB client (`php-mysqli` does the probing), and
  no unused PHP extensions.
- **Multi-stage parallelism** — the WordPress Dockerfile fetches the WP tarball and
  WP-CLI in a **side stage** that BuildKit runs *concurrently* with the PHP package
  installation; native `tar` extraction is far faster than WP-CLI's PHP-based unzip.
- **MariaDB image trimmed** from 318MB to **160MB**: the monolithic Alpine package
  ships an embedded server, a test client, and RocksDB/Aria/MyISAM offline tools that
  the stack never executes (the storage engines themselves live inside `mariadbd`);
  they are deleted in the same layer, which also speeds up image export.
- **Layer ordering** — packages → downloads → configs, so editing a config file
  rebuilds in ≤2s; `COPY --chmod` avoids extra chmod layers.
- **BuildKit everywhere** — parallel service builds (`COMPOSE_BAKE=true`), no
  provenance/SBOM attestation overhead (`BUILDX_NO_DEFAULT_ATTESTATIONS=1`).
- **BuildKit cache mounts** keep downloaded `.apk` files and the WP tarball across
  package-layer changes (package-list edits, future base bumps). Docker 29+ discards
  cache mounts on `--no-cache`, so cold benchmarks stay honest and virgin machines are
  unaffected; downloads into the cache are atomic (tmp + rename) so an aborted fetch
  can never poison it. The `CACHE_BUST` build arg forces package layers to re-run
  against the warm cache (that's the bench's "pkg-cached" scenario).

### 8.2 Boot-time

- **Zero-download first boot** — WordPress core is copied from the image
  (`/usr/src/wordpress`), not downloaded. This is also a correctness fix: it is
  deterministic and immune to Docker's volume copy-up semantics (a previous
  `--skip-content` approach produced a site with **no themes** — a blank page).
- **`mariadbd --bootstrap` init** — replaces the classic
  start-temp-server → poll → SQL → shutdown dance with one direct SQL application.
- **Fast readiness detection** — all healthchecks use `--start-interval=500ms`:
  during startup, readiness is polled twice a second instead of every 3s, removing up
  to ~3s of dead time *per dependency hop*.
- **Meaningful healthchecks** — MariaDB is "healthy" only when the *application user*
  can connect over TCP (exactly what WordPress needs); WordPress when php-fpm accepts
  FastCGI connections; nginx when HTTPS answers. `depends_on: service_healthy` chains
  them, so each service starts exactly when the layer below is usable.
- **Fewer PHP boots during install** — `wp-config.php` is written by heredoc (with
  locally generated salts) instead of `wp config create`, and the full-tree
  `chown -R` was replaced by a targeted `find -user root` (the copied tree already
  carries the right ownership from the image).

### 8.3 Measured results (idle 8-core machine, Docker 29)

| Metric | Before rework | After |
|---|---|---|
| True cold build (`--no-cache --pull`, empty caches) | 25.8s | **~13s** |
| Package-layer rebuild (warm caches) | — | **~7s** |
| Config-change rebuild | 3.9s | **≤2s** |
| Fresh first boot → live site | 14.4s *(blank, broken site)* | **~7s (working site)** |
| Warm restart → live site | — | **~3.5s** |
| Full pipeline, virgin machine (`make`) | ~40s (broken site) | **~20s** |
| Images total | 578MB | **420MB** (mariadb 160, wordpress 244, nginx 16) |

Methodology notes: "true cold" is honest — Docker 29 discards cache mounts under
`--no-cache`, and the bench additionally clears its dedicated cache IDs. Numbers
degrade substantially on a loaded machine; benchmark on a quiet one.

---

## 9. Testing & compliance

```bash
make test        # static + runtime checks — no sudo needed
make test-deep   # + kills PID 1 in each container, cycles down/up, checks persistence
```

`tests/compliance.sh` maps one-to-one to subject v5.2: repository structure and
Makefile role; **penultimate stable Alpine verified live against Docker Hub**; no
`latest`; every image built locally and named after its service; no prohibited
keep-alive hacks; network line present, no host networking, no `links:`; restart
policy; only port 443 published; two named volumes under `/home/login/data` with no
service bind mounts; secrets configured, git-ignored, absent from tracked files *and
git history*; `.env` usage; admin-username rule (statically and against the live DB);
entrypoints ending in `exec`; TLS 1.2/1.3 accepted and 1.0/1.1 rejected; certificate
identity; a real WordPress page served; exactly two WP users with a compliant
administrator; an active theme; PID 1 is the real daemon; service isolation (no nginx
in the app containers); secrets not leaked via environment; crash-restart; persistence.

### 9.1 ShellCheck and the `#!/bin/hellish` shebang

Every script under `srcs/` and `tests/` starts with `#!/bin/hellish`, and ShellCheck
only knows `sh`, `bash`, `dash`, `ksh` and `busybox sh`. On an unknown shebang it
emits SC1008 and then refuses to analyse the file at all, so the fourteen scripts
were being reported as errors while receiving no checking whatsoever.

The fix is the directive SC1008 itself asks for, on line 2 of each script:

```sh
#!/bin/hellish
# shellcheck shell=sh
```

That declaration is honest rather than a mute button. hellish describes itself as an
almost-POSIX shell diffed against `bash --posix`, and it was verified before the
directive was added: a thirty-construct battery covering the parameter expansions,
arithmetic, `case` globs, heredocs, `trap`, subshells and `read` loops these scripts
actually use produces byte-identical output under `hellish`, `dash` and
`bash --posix`; all fourteen scripts also parse identically under `hellish -n` and
`dash -n`. Under `shell=sh` ShellCheck reports zero errors across them, which means
the scripts were already POSIX-clean and the directive costs no coverage.

Do **not** put `shell=sh` in a repository-level `.shellcheckrc`. That key overrides a
real `#!/bin/bash` shebang rather than acting as a fallback, so it would raise false
SC3044/SC3054 "undefined in POSIX sh" warnings on the bash scripts in the
`vendor/scripts` submodule. Per-file directives are scoped correctly; a root config
is not.

If a script ever needs a genuine hellish extension that POSIX lacks, the directive
becomes a lie and ShellCheck will say so. Fix the script rather than the directive.

**Pre-submission checklist:**

- `make test-deep` fully green.
- Re-run near the defense date: the "penultimate stable Alpine" target moves when
  Alpine releases — the suite checks Docker Hub live and will tell you to bump.
- The history check (S15) fails until old credential-bearing commits are rewritten
  out of the repository — the subject makes repo credentials an automatic failure.

---

## 10. Defense preparation Q&A

### Docker fundamentals

**How does Docker work?** The Docker daemon builds images (immutable, layered
filesystems) and runs containers — processes isolated with kernel *namespaces* (pid,
net, mnt, uts, ipc) and resource-limited with *cgroups*, sharing the host kernel.
That's why containers start in milliseconds and weigh megabytes, unlike VMs which
virtualise hardware and boot a full OS.

**Image vs container?** An image is the read-only template (layers + metadata); a
container is a running instance of it with a writable layer on top. `docker images`
vs `docker ps`.

**What is Docker Compose and why the Makefile?** Compose declaratively describes
multi-container applications (services, networks, volumes, secrets) in one YAML and
manages their lifecycle. The subject requires a root Makefile as the entrypoint that
builds everything *through* docker-compose.yml — here `make up` also auto-provisions
config, secrets and TLS before calling Compose.

**Why `alpine:3.23`?** The subject demands the *penultimate stable* version of Alpine
or Debian. At the time of writing, latest stable is 3.24 → penultimate is 3.23.
Alpine was chosen for size (~5MB base) and build speed. `make test` re-verifies this
against Docker Hub live, because the target moves with new Alpine releases.

**Why is pulling ready-made images forbidden / what do your Dockerfiles do?** The
point of the project is writing the service setup yourself. Each Dockerfile starts
`FROM alpine:3.23`, installs the service from Alpine packages, copies hand-written
configuration, and sets a custom entrypoint script. `make test` proves the running
images are local builds.

### NGINX & TLS

**Why is NGINX the only entrypoint?** Defense in depth: one hardened door. Only
nginx publishes a port (443); WordPress and MariaDB have no published ports and are
only reachable over the internal bridge network.

**Where is TLS configured, and how do you prove only 1.2/1.3 work?**
`ssl_protocols TLSv1.2 TLSv1.3;` in the nginx vhost. Live proof:

```bash
openssl s_client -connect dlesieur.42.fr:443 -tls1_2   # succeeds
openssl s_client -connect dlesieur.42.fr:443 -tls1_3   # succeeds
openssl s_client -connect dlesieur.42.fr:443 -tls1_1   # fails
curl http://dlesieur.42.fr/                            # connection refused (no port 80)
```

**How does the certificate chain work?** `make setup` creates a local Root CA on the
host and signs a server certificate for the domain (SANs: domain, localhost,
127.0.0.1). Only the server cert/key are mounted into nginx as Docker secrets — the
CA key stays on the host, because `make trust` makes browsers trust that CA, so it
must never be exposed to a container.

### WordPress & php-fpm

**What is php-fpm and why "without nginx"?** php-fpm (FastCGI Process Manager) is a
pool of PHP worker processes speaking the FastCGI protocol on port 9000. The subject
wants separation of concerns: the WordPress container runs *only* php-fpm; nginx (in
its own container) forwards `.php` requests to it and serves static files itself from
the shared read-only volume.

**How is WordPress installed without ever touching a browser wizard?** WP-CLI, driven
by the entrypoint on first boot: deploy core from the image, write `wp-config.php`,
`wp core install` (site + admin user), `wp user create` (editor). Credentials come
from Docker secrets; config from environment variables.

**Why can't the admin be called "admin"?** Subject rule (obvious-target hardening).
It is enforced: the entrypoint refuses to start with a non-compliant name, and the
test suite checks both `.env` and the live database. The database contains exactly
two users: one administrator (`superuser`) and one editor.

### MariaDB

**How does the database get initialised?** First boot only: `mariadb-install-db`
creates the system tables, then `mariadbd --bootstrap` applies idempotent SQL (root
password, application database, application user, grants) directly — no temporary
server, no client, no network. A marker file written only after success makes an
interrupted init retry cleanly. Remote root login is not created; the app user
connects from the WordPress container with the secret password.

**How do you connect to it manually?**
`docker exec -it mariadb mariadb -u wpuser -p wordpress` (or as root via unix socket
credentials) — then `SHOW TABLES;` shows the `wp_*` schema.

### Docker mechanics the subject insists on

**What is PID 1 and why does every entrypoint end with `exec`?** PID 1 inside a
container is init: it receives the signals Docker sends (`docker stop` → SIGTERM) and
must reap orphaned children. `exec` replaces the shell with the daemon, so the daemon
*is* PID 1 — clean shutdowns, no zombies. Proof: `docker exec <c> ps -o pid,comm`
shows `nginx`/`php-fpm84`/`mariadbd` at PID 1. That's also why `tail -f`,
`sleep infinity`, `while true` or a bare `bash` are prohibited: they'd keep the
container "alive" with a fake init in front of (or instead of) the real service.

**How do the containers restart after a crash?** `restart: unless-stopped` on all
services. Live demo: `docker exec nginx kill 1` — the container exits and comes back
within seconds (`make test-deep` automates this for all three). `unless-stopped` was
chosen over `on-failure` deliberately: killing PID 1 with SIGTERM makes daemons exit
*gracefully* (code 0), which `on-failure` would **not** restart. Manual `docker stop`
still stays stopped.

**How do Docker secrets work here?** Compose mounts each secret file at
`/run/secrets/<name>` (mode 0400) inside exactly the services that need it. Nothing
secret is in the image, the compose file, the environment, or Git —
`docker inspect wordpress` shows only non-sensitive variables.

**How does the network work?** One user-defined bridge network `inception` declared
in the compose file (the "network line"). Docker's embedded DNS resolves service
names (`fastcgi_pass wordpress:9000`, DB host `mariadb`). `network: host` and
`links:` are forbidden — host networking would drop all isolation and publish
everything.

**Named volumes vs bind mounts — and what are those `driver_opts`?** Services mount
*named volumes* only. The volumes themselves are declared with the `local` driver and
a `device:` bind option, which is what makes a *named volume* store its data at the
subject-mandated path `/home/login/data`. `docker volume inspect inception_db_data`
shows both the name and the device.

**What happens on a second boot?** Both init guards short-circuit (marker file /
`wp-config.php` present), so a restart is just "start the daemons" — ~3.5s to a live
site. Corollary: changing secrets after first boot requires `make clean && make`.

### Live-proof cheat sheet (run these during the defense)

```bash
make test-deep                                   # the whole subject, automated
make status                                      # 3 × Up (healthy)
docker exec nginx  ps -o pid,comm                # PID 1 = nginx
docker exec nginx  kill 1 && sleep 5 && make status   # crash-restart proof
docker volume inspect inception_wp_data          # named volume + device path
docker exec wordpress wp --allow-root user list  # the two users, admin rule
make bench                                       # build performance, honest cold
```

### Typical "small modification" requests — where to touch

| Ask | Where |
|-----|-------|
| Change the domain | `DOMAIN_NAME` in `srcs/.env` → `make up` re-issues the cert; `/etc/hosts` entry |
| Change site title / user names | `srcs/.env` → `make clean && make` (install-time values) |
| Add a WP user | `docker exec wordpress wp --allow-root user create <login> <email> --role=author` |
| Change upload size | `client_max_body_size` (nginx conf) **and** `conf/uploads.ini` (PHP) → rebuild |
| Change PHP tuning | `conf/www.conf` / `conf/opcache.ini` → rebuild (≤2s) |
| Bump PHP version | four coupled places: wordpress Dockerfile (packages, paths, healthcheck), `www.conf` COPY path, entrypoint `exec php-fpm84`, Makefile `run_wp` |
| Add a bonus service | new `srcs/requirements/<svc>/` context + service block in compose (own container, own volume if stateful, extra port allowed for bonus) |
| Add an API route | `bonus/api/app/server.js` routes table + a handler; a new cache key goes in `cache.js` with its own TTL and its invalidation |
| Change what the machine room shows | `bonus/web/app/src/components/hero/Daemons.ts` (events, gags), `sprites.ts` (art) → `make re-web` |
| Add a wire to the machine room | API: `bonus/api/app/traffic.js` (`WIRES`, plus a recorder or a sampler); web: `lib/wires.ts` (same id, a lane where it overlaps no other wire) → rebuild both |
| Refresh the site's build-time data | `make snapshot && make re-web` |
| Bump Astro or mysql2 | `package.json` → `make lock` → rebuild |

---

## 11. The documentation website (site/)

The WordPress site itself hosts this documentation as a terminal-styled blog —
custom theme + plugin, fully **baked into the image** so `make re` or a fresh
clone reproduces it with zero manual steps.

```text
srcs/requirements/wordpress/site/
├── install.sh                    # entrypoint hook: sync files + run seed.php (idempotent, non-fatal)
├── seed.php                      # ONE wp eval-file process: activate, permalinks, pages/posts/menu
├── plugin/inception-kit/         # reusable PHP components: [term_window] [cmd] [out]
│                                 #   [callout] [stats] [arch] [kbd] [badge] + helpers (icons,
│                                 #   prompt, reading time) reused by the theme
├── theme/inception-terminal/     # v2 "the page is one shell session" — figlet hero,
│                                 #   ls -la docs index, log-stream journal, serif reading
│                                 #   voice for prose, system fonts only, WCAG AA,
│                                 #   reduced-motion safe, zero external assets
└── content/                      # seed content: 5 doc pages + 4 journal posts (HTML + shortcodes)
```

- **Editing:** change anything under `site/`, then `make up` — the container is
  recreated and `install.sh` re-syncs theme/plugin files (repo is the source of
  truth). Content pages are seeded **once** (marker option
  `inception_site_seeded`); to re-seed:
  `docker exec wordpress wp --allow-root option delete inception_site_seeded && make restart`.
- **Writing from wp-admin (the normal way):** WordPress *is* the authoring
  interface — any page/post written in the block editor renders in the shell UI
  automatically. The kit components are insertable as **block patterns**
  (inserter → Patterns → *Inception Kit*: command, output, terminal window,
  callouts, stat tiles, diagram), the editor canvas itself is themed dark
  terminal (`editor.css`), and the theme palette is exposed as colour swatches.
  Admin-created pages are added to the nav via *Appearance → Menus*; the seeder
  never touches content it didn't create.
- **Boot cost:** the whole provisioning runs in a single PHP process — a fresh
  first boot including full seeding measures ~7s, same as before the site existed.
- **Failure isolation:** the entrypoint calls `install.sh` non-fatally; a broken
  seed can never prevent php-fpm from starting.
- **Gotcha:** WordPress runs `wpautop`/`texturize` before shortcodes — the kit
  registers its shortcodes in `no_texturize_shortcodes` and strips injected
  `<br/>` tags, otherwise `--flags` in commands render as dashes.

---

## 11.1 Bonus: static website (no PHP)

Subject's bonus list, item 3: *"Create a simple static website in the language of
your choice except PHP."* This is a **separate service from WordPress**, not a page
rendered by it — WordPress itself is mandatorily PHP (`php-fpm`), so there is no such
thing as a "PHP-free WordPress page"; the bonus rule targets an independent site.

```text
srcs/requirements/bonus/staticsite/
├── Dockerfile              # alpine:3.23 + nginx only — same base/conventions as
│                            #   the mandatory services, no PHP package installed
├── conf/nginx.conf         # plain HTTP, port 8090, static files only, no fastcgi
├── tools/entrypoint.sh     # exec nginx as PID 1 — same pattern as every other
│                            #   entrypoint in this repo (§6)
└── site/                   # index.html + style.css + script.js — hand-written,
                             #   zero external requests (no CDN fonts/JS/images),
                             #   vanilla JS only (typing effect, live clock, a
                             #   canvas background), prefers-reduced-motion safe
```

- **Container:** `staticsite`, image `staticsite:inception` — same naming
  discipline as the mandatory services (§3).
- **Network:** on the `inception` bridge network for consistency, but talks to
  nothing else on it — no `depends_on`, no secrets, no shared volume. It is
  reachable at `http://<login>.42.fr:8090` (plain HTTP: it carries no credentials,
  so TLS wasn't judged necessary — trivial to add the same cert/secrets pattern as
  nginx if a defense asks for it).
- **Why nginx again, if the rule excludes PHP?** The excluded language is PHP —
  the constraint is about how the *site* is authored (plain HTML/CSS/JS, no PHP
  templating), not about which web server transports the bytes. Reusing nginx
  keeps the image minimal and consistent with the rest of the project instead of
  introducing a second, unrelated web-server technology for no benefit.
- **Port choice:** 8090, picked simply because it's free and outside the
  well-known-port range; the subject explicitly allows bonus services to open
  extra ports (§VIII of the subject).
- **Compliance-suite scoping:** `tests/compliance.sh` S10 originally grepped the
  *entire* compose file for any `ports:` block, which would have false-failed once
  a second (legitimate, bonus) `ports:` entry existed. It now checks nginx's own
  service block specifically (`svc_block nginx`) and separately asserts that
  `wordpress`/`mariadb` still publish nothing — R02 was already scoped correctly
  (it filters `docker ps` down to `nginx|wordpress|mariadb`) and needed no change.
- **Editing the content:** change anything under `site/`, then `make up` — the
  container rebuilds and re-serves the new files immediately (no seeding, no
  database, nothing to reset).

---

## 12. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| A container restart-loops | `docker logs <name>` — entrypoints fail fast with explicit messages |
| `error 1290 ... skip-grant-tables` in mariadb logs | The bootstrap SQL must keep its leading `FLUSH PRIVILEGES;` (grant tables aren't loaded in `--bootstrap` mode) |
| nginx crash-loop: `shared memory zone "SSL"` | Alpine's main nginx.conf already defines the SSL session cache — don't redeclare `ssl_session_cache` in the vhost |
| Changed a password but nothing applies | Init guards (§6) — values are baked at first boot: `make clean && make` |
| Browser says the certificate is untrusted | Expected with a local CA — accept once or run `make trust` |
| `make bench` numbers look bad | Machine load skews everything — benchmark on a quiet machine (see §8.3) |
| Compose errors about missing secret files | Run through `make` (not raw compose): `make setup` provisions secrets and certs first |

---

## 11. Bonus services

Each is its own container, built from its own Dockerfile on `alpine:3.23`, with
a healthcheck and a real daemon as PID 1 — the same rules the mandatory services
follow. Sources in `srcs/requirements/bonus/`.

### 11.2 Redis object cache

Three parts have to line up, and it is the third that is usually missed:

1. `php84-pecl-redis` in the WordPress image (the PHP extension).
2. `WP_REDIS_HOST`, `WP_REDIS_PORT`, `WP_CACHE_KEY_SALT` and `WP_CACHE` in
   `wp-config.php`. The salt is the domain, so two installs sharing a Redis
   instance cannot read each other's keys.
3. **The drop-in.** `wp redis enable` writes `wp-content/object-cache.php`.
   Without it the plugin is installed, active, and caching nothing.

The entrypoint does all three, **non-fatally** — the site must boot even if
Redis is unreachable, because a cache is an optimisation, not a dependency.
It also patches an *existing* `wp-config.php`: the config heredoc only runs on a
first install, and the site volume outlives image rebuilds.

Redis is configured as a cache, not a database — `save ""`, `appendonly no`,
`maxmemory 256mb`, `maxmemory-policy allkeys-lru`. Without an eviction policy
Redis answers writes with an error once full, which WordPress would surface as a
broken page rather than a cache miss.

### 11.3 FTP

`pure-ftpd`, configured entirely by command-line flags built in the entrypoint
from `conf/pure-ftpd.conf`.

The interesting part is permissions. WordPress files are owned by `nobody`
(uid 65534). Rather than `chmod -R g+w` across ~2600 files, the image adds a
second `/etc/passwd` entry sharing that uid:

```text
ftpuser:x:65534:65534:FTP:/var/www/html:/sbin/nologin
```

Two names for one uid is ordinary Unix. The FTP user *is* the owner, so nothing
needs relaxing and permissions cannot drift out of step with php-fpm. The login
shell must also appear in `/etc/shells` or the account is refused, even though
it must never get a shell.

**Why not vsftpd.** It was the first implementation and it works for ordinary
clients, but on Alpine it dies under rapid connect/disconnect — the pattern a
port scan produces. Measured: 3 to 5 crashes per 60 abrupt closes, which the
restart policy quietly absorbed as a climbing `RestartCount` while the service
still reported healthy. `isolate=NO`/`isolate_network=NO` reduced it but did not
remove it, and `one_process_model=YES` stopped the crashes by breaking FTP
entirely (no listings, no uploads). pure-ftpd survived the identical test —
100 abrupt closes, zero restarts — so that is what ships.

Two vsftpd traps worth recording anyway, since both cost real time:
`vsftpd_log_file=/dev/stdout` makes it refuse every connection with
`500 OOPS: failed to open vsftpd log file`, because it reopens the log after
dropping privileges and chrooting when the `/proc/self/fd` symlink no longer
resolves; and `syslog_enable=YES` silently discards everything, because a
single-service container has no syslog daemon and therefore no `/dev/log`.

**Passive mode only**, ports 21000-21010 published 1:1 — the advertised range
and the reachable range must be identical or every directory listing hangs —
advertising `127.0.0.1`, which serves the VM and the physical host alike
because both reach the server over loopback.

The healthcheck reads the listening socket from `/proc` with `netstat` rather
than opening a connection: under vsftpd the obvious `nc -z` was itself killing
the daemon every ten seconds, and a healthcheck should observe a service, not
exercise it.

### 11.4 Adminer

Pinned to a release **and its SHA-256**, verified at build time — this container
talks to the database, so its integrity is checked rather than assumed. Served
by PHP's built-in server, which keeps it to one process; fronting a php-fpm pool
with nginx would put two daemons in a container for a single-file admin page.

### 11.5 Scheduled backups (free choice)

`crond` as PID 1 — a real daemon, not a keep-alive loop. An initial backup runs
at startup so the service is demonstrably working rather than merely scheduled,
and so the healthcheck has something to verify. The healthcheck asserts a
**valid** dump exists (`gzip -t`), not that the process is alive.

Environment is written into the crontab line itself, because cron jobs do not
inherit the container's environment.

| Variable | Default | Meaning |
|---|---|---|
| `BACKUP_CRON` | `0 */6 * * *` | schedule |
| `BACKUP_KEEP` | `7` | how many dumps to retain |

Data lives in the `backup_data` named volume → `/home/dlesieur/data/backups`,
following the same host-path rule as the two mandatory volumes.

### 11.6 A note on nginx and container IPs

`fastcgi_pass` uses a variable plus an explicit `resolver 127.0.0.11`:

```nginx
resolver               127.0.0.11 valid=10s ipv6=off;
set $upstream_wordpress wordpress:9000;
fastcgi_pass            $upstream_wordpress;
```

With a literal `fastcgi_pass wordpress:9000;` nginx resolves the name once when
it loads its config and caches that address for the life of the process.
Recreate the wordpress container — a rebuild, a crash, any
`docker compose up -d wordpress` — and it returns on a new IP while nginx keeps
dialling the old one, answering **502 on every request** until nginx itself is
restarted. Putting the upstream in a variable forces re-resolution per request.
Verified by moving wordpress from `172.18.0.9` to `172.18.0.10` without touching
nginx: the site stayed at 200.

The lab's `/lab/` and `/api/v1/` locations get the same re-resolution from an
`upstream` block with `server … resolve`, which also keeps connections alive; a
variable cannot (§13.1).

---

## 13. The lab: `web` + `api` (bonus, free choice)

Two more containers, same rules as every other service: own Dockerfile on
`alpine:3.23`, own healthcheck, a real daemon as PID 1, no published port.
nginx is the only way in.

```text
browser ──TLS :443──► nginx ─┬─ /            fastcgi ► wordpress:9000
                             ├─ /lab/        http    ► web:8080   (static files)
                             └─ /api/v1/     http    ► api:3000   (JSON)
                                                          ├─► mariadb:3306  database `lab`, user `labuser`
                                                          └─► redis:6379    cache, counters, rate limits
```

- **`web`** (`srcs/requirements/bonus/web/`). An Astro 5 site rendered to HTML
  at image build time, served by an unprivileged nginx (`USER nginx`, pid and
  temp files in `/tmp`). The runtime image has no node, no npm and no
  `node_modules`: 12.8 MB.
- **`api`** (`srcs/requirements/bonus/api/`). `node:http` with no framework. The
  only runtime dependency is `mysql2`; the Redis client is hand-written RESP2
  over `node:net` (`app/redis.js`). It starts as root to read the secret, then
  drops to the `api` user (uid 1001). Image 86.2 MB.
- **The machine room** (`/lab/`). A pixel-art diorama of the stack on one
  `<canvas>`, driven by `/api/v1/stats`. Its design contract is
  `srcs/requirements/bonus/web/DESIGN.md`.

### 13.1 Edge routing

`srcs/requirements/nginx/conf/nginx.conf` gains two `^~` prefix locations. `^~`
matters: it stops the regex locations from matching, so
`/lab/_astro/x.js` is proxied instead of being looked for under
`/var/www/html`. `absolute_redirect off` keeps nginx's own redirects
(`/lab` → `/lab/`) relative, so they survive a remapped port.

Both proxy to an `upstream` block, `lab_web` and `lab_api`, instead of the
variable WordPress uses (§11.6):

```nginx
upstream lab_api {
    zone              lab_api 64k;
    resolver          127.0.0.11 valid=10s ipv6=off;
    server            api:3000 resolve;
    keepalive         32;
    keepalive_timeout 4s;   # node closes an idle keep-alive socket after 5 s
}
```

- **`keepalive`**. nginx reuses connections to the upstream. A variable in
  `proxy_pass` rules that out, so each request opens a connection and leaves it
  in TIME_WAIT for a minute. Measured with the variable: 3 300 req/s to
  `/api/v1/` filled the nginx container's whole local port range (28 267
  sockets) in 9 s, and every request after that got a 502. With the pool:
  12 700 req/s for 8 s, no errors, a few hundred sockets.
- **`resolve`** (nginx 1.27.3 and later; the image runs 1.28.3). The name is
  re-resolved through Docker's DNS, so `web` or `api` recreated on a new IP is
  found again without an nginx restart. Verified by recreating both while other
  containers held their old addresses: 502 for about 5 s, inside the
  `valid=10s` window the variable also has, then 200.
- **`keepalive_timeout 4s`** stays under the upstream's own idle timeout, so
  nginx never picks a connection the other end is closing.

WordPress keeps its variable. The load is not on the FastCGI side, and the
mandatory location stays as it was.

### 13.2 Configuration

| Variable (`srcs/.env`) | Default | Used by |
|---|---|---|
| `API_DB_HOST` / `API_DB_PORT` | `mariadb` / `3306` | api |
| `API_DB_NAME` | `lab` | api, and the mariadb entrypoint that creates it |
| `API_DB_USER` | `labuser` | api, and the mariadb entrypoint that creates it |
| `API_REDIS_HOST` / `API_REDIS_PORT` | `redis` / `6379` | api |
| `API_FPM_HOST` / `API_FPM_PORT` | `wordpress` / `9000` (defaults in `config.js`, not in `.env`) | api, for the nginx → wordpress wire (§13.5) |

The API's database credential is the Docker secret `api_db_password`
(`secrets/api_db_password.txt`, generated by `make setup`), mounted into `api`
and `mariadb` only. On every boot the MariaDB entrypoint creates (or reconciles) the `lab`
database and a user that can reach nothing else. The API applies
`app/schema.sql` on every start, and every statement is idempotent.

**Rotating the lab password.** The MariaDB entrypoint reconciles every user
with the mounted secrets on each boot (`ALTER USER` in its bootstrap SQL), so a
new secret takes effect on restart. The API's connection pool keeps retrying
until MariaDB accepts the new value:

```bash
openssl rand -base64 24 | tr -d '/+=' > secrets/api_db_password.txt
make restart
```

**Resetting the lab data** without touching WordPress:
`DROP DATABASE lab;` as root, then `make restart`. The API recreates the schema
and the seed flights.

### 13.3 API

| Route | Cache-Control | Notes |
|---|---|---|
| `GET /api/v1/` | `no-store` | lists the routes |
| `GET /api/v1/healthz` | `no-store` | 200 when MariaDB and Redis answer, else 503 with which one failed |
| `GET /api/v1/flights` | `public, max-age=5` | last 100, cache-aside, `X-Cache: HIT` or `MISS` |
| `GET /api/v1/flights/:id` | `public, max-age=30` | cache-aside |
| `POST /api/v1/flights` | `no-store` | 201 + `Location`; rate-limited |
| `GET /api/v1/guestbook` | `no-store` | last 50, cache-aside |
| `POST /api/v1/guestbook` | `no-store` | 201; rate-limited |
| `GET /api/v1/stats` | `no-store` | counters + gauges that drive the machine room |
| `GET /api/v1/traffic` | `no-store` | Server-Sent Events, the wires (§13.5); 4 streams per address, 64 in all |

**Errors** always have one shape, `{"error":{"code","message","field?"}}`.
Validation is an allowlist. An unknown field is a 422 `unknown_field` naming it,
and every other 422 names the field it rejects. A wrong method gets a 405 with
an `Allow` header, a non-JSON body a 415, and more than 16 KB a 413.

**Cache keys.** The TTL is set per entity, never globally. The `v1` suffix lets
a shape change ship without a flush.

| Key | TTL | Invalidated by |
|---|---|---|
| `lab:flights:all:v1` | 60 s | every POST /flights; a minute tick that moves a flight |
| `lab:flights:<id>:v1` | 300 s | creating that flight; a minute tick that moves it |
| `lab:guestbook:recent:v1` | 10 s | every POST /guestbook |
| `lab:stats:tables:v1` | 5 s | every write |
| `lab:stats:<counter>` | none | not a cache: the durable copy is `lab.stats` in MariaDB |
| `lab:rl:<bucket>:<ip>` | the window | fixed window; fails open if Redis is down |

**Counters.** Each event is `INCRBY` in Redis (hot) and a local delta. Every
2 s the deltas are added to `lab.stats` in MariaDB (durable), then Redis is
reconciled upward. A Redis restart can make a counter briefly low, never
permanently.

**Rate limits.** Flights allow 10 per minute per address, the guestbook 5. The
count happens before validation, so invalid requests use up the window too.
The address comes from nginx's `X-Real-IP`.

**Minute tick.** The API's own timer runs on every minute boundary. It moves
flights from boarding to en-route after 30 s and to landed after 3 min, and it
deletes the list key and each moved flight's key.

**Lifecycle.** The entrypoint waits for MariaDB (at most 90 s) and Redis (at
most 30 s) with bounded `nc -z` loops, then runs `exec node`. Inside, a pool
with capped backoff absorbs a database that accepts TCP before it accepts
logins. On SIGTERM the API stops accepting and closes idle keep-alive sockets.
It then waits up to 10 s for in-flight requests, flushes the counters, closes
the pool and Redis, and exits 0. Logs are one JSON object per line on stdout.

### 13.4 Web

- **Build-time content.** Pages that show database rows are rendered from JSON
  snapshots in `web/app/src/data/` (`flights.json`, `stats.json`,
  `stack.json`). `make snapshot` refreshes them from the running API through
  nginx and reads the daemon versions with `docker exec`. `make re-web` then
  rebuilds and replaces the `web` container only.
- **A flight created after the build** has no page on disk. nginx serves
  `404.html`, and its script recognises `/lab/flights/<id>/` and draws that
  flight from the API.
- **No inline code.** The CSP is `script-src 'self'; style-src 'self'` with no
  `unsafe-inline`. Astro is set to `inlineStylesheets: 'never'` and Vite to
  `assetsInlineLimit: 0`. Meters are text (`█░`), not inline widths.
- **Caching.** `/lab/_astro/*` is hashed, so it is `immutable` for a year. HTML
  is `no-cache`. Fonts get 30 days.
- **What runs in the browser.** No framework and no third party. Each live part
  is a module script that attaches to markup already on the page. There are no
  `client:*` islands, because there is no component framework to hydrate.

| Script | Loaded on | Why at load |
|---|---|---|
| `lib/boot.ts` (status bar, keymap, palette, poll loop) | every page | the keyboard is the primary input |
| `hero/Daemons.ts` (machine room) | `/lab/` | its loop runs only while the canvas is visible |
| `islands/counters.ts`, `flight-table.ts`, `cabinets.ts` | where those tables are | swap numbers when a poll answers |
| `islands/dispatch.ts`, `guestbook.ts` | forms | send JSON, show the API's own error |
| `lib/traffic.ts` (the wires stream) | `/lab/`, and `:wires` anywhere | opens only while the room panel is on screen |

Measured JavaScript on `/lab/`: 14.2 KB gzipped, against a 30 KB budget (checked
by `make test-lab`, L11).

**The engine** (`hero/Daemons.ts`). It runs a fixed 60 Hz simulation inside
`requestAnimationFrame`, catching up at most one second. The canvas is 320×160
logical pixels scaled by an integer factor in device pixels, and sprites are
rasterised once from ASCII art in `hero/sprites.ts`. The loop pauses when the
canvas leaves the viewport or the tab is hidden. With `prefers-reduced-motion`
there is no loop at all: one still frame is drawn whenever the data changes.
Every movement is tied to an API event; `DESIGN.md` §4 has the table.

**Keys.** `Alt+1…4` switch pages, `:` opens the command palette, `/` filters
(or opens the palette), `?` shows the cheatsheet, `gg`/`G` jump to top or
bottom, and `j`/`k` scroll. No shortcut fires while an input has focus. The
palette's commands are `help`, `goto`, `flights`, `flight <id|callsign>`,
`stats`, `health`, `dispatch <from> <to> [kb] [note]`, `theme`, `q`.

### 13.5 The wires: live traffic on the machine room's cables

The cable duct under the machine room's floor has three lanes, and six wires
run in them. Every request, command or statement on a wire is a dot. Its
colour says what happened and its timing is real. Only its speed is slowed
for the eye: a dot takes half a second to cross, whatever the wire's length. A
panel on the canvas wall and a table under the canvas give each wire's
requests per second, median latency, and how many requests one dot stands for.

**How each wire is known.** The API is one end of three wires and sees every
event on them. It can only count the other three.

| Wire | Source | What it gives |
|---|---|---|
| nginx → api | the request handler, on finish: status and cache verdict | every request, with latency |
| api → redis | `redis.js`, on each reply | every command, with latency |
| api → mariadb | `db.js`, on each statement, internal ones included (counters, schema, probes) | every statement, with latency |
| nginx → wordpress | php-fpm `accepted conn`, read over FastCGI (`fpm.js`) once a second | a count per second |
| wordpress → redis | Redis `INFO stats` once a second, minus the API's own commands | a count per second, with hits and misses |
| wordpress → mariadb | `SHOW GLOBAL STATUS LIKE 'Questions'` once a second, minus the API's own statements | a count per second |

A sampled wire counts every client that is not the API. In practice that is
WordPress, plus nginx's healthcheck, which fetches `/` every 10 s: a real page.
Redis `MONITOR` would give single commands, but it slows Redis down more than
the traffic it watches.

**Colours.**

| Colour | Means |
|---|---|
| cyan | a cache hit: the request was answered from Redis, or a `GET` found its key |
| yellow | a cache miss: the request went to MariaDB, or a `GET` found nothing. On api → mariadb, the statements that load a miss are yellow too (an `AsyncLocalStorage` around the loader in `cache.js`) |
| magenta | a statement over 100 ms |
| red | a 4xx or 5xx answer (429 included), an error reply, a lost command |
| white | everything else |

**Taking away the API's own share.**

- **Redis.** Replies come back in the order commands were sent on the one
  connection. `redis.info()` resolves with the client's counters as they stood
  when Redis ran the `INFO`. Every command in those counters ran before it, and
  no later one is included. Keyspace hits and misses are counted the way Redis
  counts them: `GET`, each key of `MGET`, and `TTL`. Writes are not counted.
- **MariaDB.** `db.own.statements` includes the `SHOW` itself, and so does
  `Questions`. A statement still in flight on another pool connection can make
  one sample come out at −1. That −1 is carried into the next sample instead of
  being clamped to 0, so no phantom request appears and none is lost.
- **php-fpm.** Two findings, each measured before anything was built on it:
  1. nginx forwards PHP with `fastcgi_keep_conn on` but has no upstream
     keepalive pool. It asks php-fpm to keep the connection, then closes it.
     php-fpm counts the request, then counts again while waiting for a next
     request on that connection. Measured: a page counts 2 (40 of 40 requests)
     and a plain FastCGI request such as the API's status read counts 1 (3 of
     3). Hence `config.fpm.countsPerRequest = 2`. `tests/lab.sh` L26 fails if
     ten page views stop reading as ten.
  2. An empty TCP connection counts as well (20 of 20). WordPress's healthcheck
     was `nc -z 127.0.0.1 9000` every 3 s, which drew a request that never
     happened on the wire every 6 s. It now reads the listening socket with
     `netstat`, the same rule as the FTP healthcheck (§11.3). The check is no
     weaker: the kernel completed nc's handshake from the listen backlog
     whether php-fpm could serve or not.

  The status page (`pm.status_path = /fpm-status` in `www.conf`) is not
  reachable through nginx. Every request nginx forwards names a real `.php`
  file in `SCRIPT_NAME`. L27 checks this.

**Delivery.** `GET /api/v1/traffic` answers with `text/event-stream`.

- **Batches.** One frame every 200 ms carries everything since the last
  frame, never one message per request. A frame has per-wire counts by
  outcome, its window, and the p50 over the last second. When a wire had 48
  events or fewer, each event's offset in the window is included too, so a
  burst replays with its real spacing. Sampled wires arrive once a second. An
  idle stream still gets one frame a second, so the page can tell quiet from
  gone.
- **No buffering.** `X-Accel-Buffering: no` turns nginx's buffering off for
  this response only. L24 checks that frames arrive within 1.5 s.
- **Nothing runs unwatched.** Nothing is recorded or sampled while no stream is
  open. The page holds its stream only while the machine room panel is on
  screen and the tab is visible.
- **Slow clients.** A client that cannot keep up loses frames
  (`writableNeedDrain`); the API never buffers for it.
- **Limits.** 4 streams per address (429) and 64 in all (503).
- **Shutdown.** A stream does not count as in flight for the SIGTERM drain.
  Shutdown sends `event: bye`, ends every stream, then drains, and
  `EventSource` reconnects on its own. L22 (`--deep`) checks this.

**In the browser** (`lib/traffic.ts`, `hero/Daemons.ts`). There is one
`EventSource`, opened and closed by leases: the room holds one while visible,
and `:wires` holds one for a moment.

- **Rate.** A wire's rate is the sum of the last second of frames, or the last
  sample for a sampled wire.
- **Scale.** Past 60 dots on one wire at once, a dot stands for 2, 5, 10 or
  more requests. The scale steps back down only below half that, so it does
  not flap.
- **Colours stay true.** Each outcome carries its own remainder, so colours
  keep their true proportions, and a rare error still gets its dot, only later.
- **Reduced motion.** With `prefers-reduced-motion` no dots are drawn, but the
  panel and the table still update.

**Measured.** 64 keep-alive connections sending GETs through nginx, 8 s per
phase, on a 42 workstation:

| | nobody watching | the room open in a browser |
|---|---|---|
| requests per second through nginx | 12 691 | 12 596 |
| errors | 0 | 0 |
| API CPU | 101 % of a core | 94 % of a core |
| browser frames | — | 60 fps, p95 16.7 ms, worst 16.8 ms |
| wires table | — | nginx → api 13 579/s at 200 requests per dot; api → redis about three times that (a `GET` and two `INCRBY` per request) |

The throughput difference is within noise. While someone watches, recording is
an array push per event; while nobody does, it is a boolean test.

### 13.6 Node without Node on the host

No `node` or `npm` ever runs on the host. `nodetool:inception`
(`srcs/requirements/bonus/nodetool/`) is a CLI image with the same
`alpine:3.23` + `apk add nodejs npm` as the build stages. Like 42ctl, it is not a
compose service.

```bash
make lock                                    # re-resolve both package-lock.json files
make npm-web NPM="outdated"                  # any npm command, in the web app directory
make npm-api NPM="install mysql2@3.24.4 --package-lock-only"
```

### 13.7 A host with rootless Docker and a small home (42 workstations)

Two git-ignored files adapt the stack to such a host. The graded
`docker-compose.yml` is unchanged, and on the VM neither file exists.

| File | What it changes |
|---|---|
| `srcs/docker-compose.local.yml` (from the `.example`) | Rootless Docker cannot bind 443, so ports are remapped (nginx `9443:443`). The volumes are renamed `*_local` and pointed at `$INCEPTION_DATA_DIR`. |
| `srcs/local.mk` (from the `.example`) | `DATA_DIR=/goinfre/<login>/inception-data` holds the volumes on the local disk. `DOCKER_CONFIG` keeps the Docker CLI's state on sgoinfre instead of the home directory. |

Why `/goinfre` and not sgoinfre for the data: the sgoinfre NFS share rejects the
`chown` a container's `mysql` user needs (`chown: Invalid argument` under
rootless Docker), so MariaDB cannot initialise there. With the override,
`make test` reports S20 (`/etc/hosts`), R02 (port 443) and R13 (volume path) as
host-only differences. The same tree on the VM passes them.

Reach the site without `/etc/hosts` or sudo:

```bash
curl -k --resolve dlesieur.42.fr:9443:127.0.0.1 https://dlesieur.42.fr:9443/lab/
```

### 13.8 Tests

`make test-lab` (`tests/lab.sh`, about 35 s) runs 27 checks through the edge,
plus 2 more with `LAB_ARGS=--deep`:

| Group | Checks |
|---|---|
| containers | both healthy; PID 1 is nginx or node; neither runs as root; neither publishes a port |
| edge | TLS 1.2 and 1.3 accepted, 1.1 refused; CSP without `unsafe-inline`; no inline code; no third-party origins; immutable assets and no-cache HTML; JS budget |
| api | healthz; cache MISS then HIT with the key's TTL and a `redis-cli MONITOR` excerpt; POST invalidates; 422 names the field; unknown field; 405 + Allow; durable counters in MariaDB; no secret in `docker history`; 429 + Retry-After |
| wires | the stream is not buffered by nginx; nginx → api counts 20 GETs with their cache hits; 10 WordPress page views read as 10 on nginx → wordpress; `/fpm-status` is not public; a fifth stream from one address gets 429 |
| `--deep` | `docker stop` with a stream open → the stream gets `bye`, the API logs `shutdown: complete` and exits 0 at once; the API started before MariaDB waits, then becomes healthy |

It waits out a nearly spent rate-limit window, so it can be rerun right away.

### 13.9 Deviations from the brief

- **Sprites** are ASCII art rasterised at run time, not a `sprites.png`. They
  can be diffed and reviewed, and no image asset is needed.
- **No `:cache flush`.** An anonymous visitor must not be able to empty Redis.
- **`GET /api/v1/guestbook`** was added so the page can list entries before
  posting.
- **View transitions** use cross-document CSS (`@view-transition`), which adds no
  JavaScript, instead of Astro's client router.
- **Astro is pinned to 5.18.2** as the brief asks, although newer majors exist.
  apk packages are unpinned, like every other image here, because Alpine drops
  superseded package versions from its mirrors.
