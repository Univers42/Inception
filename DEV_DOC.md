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
| `sudo` access | needed for `/etc/hosts` and data-dir cleanup |

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

---

## 3. Architecture

```
        ┌──────────┐
Client ──► NGINX:443 │   TLS 1.2/1.3 termination — the ONLY published port
        │  (nginx)  │   serves static files directly from the shared volume (ro)
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

---

## 11. The documentation website (site/)

The WordPress site itself hosts this documentation as a terminal-styled blog —
custom theme + plugin, fully **baked into the image** so `make re` or a fresh
clone reproduces it with zero manual steps.

```
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

```
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

The interesting part is permissions. WordPress files are owned by `nobody`
(uid 65534). Rather than `chmod -R g+w` across ~2600 files, the image adds a
second `/etc/passwd` entry sharing that uid:

```
ftpuser:x:65534:65534:FTP:/var/www/html:/sbin/nologin
```

Two names for one uid is ordinary Unix. The FTP user *is* the owner, so nothing
needs relaxing and permissions cannot drift out of step with php-fpm.

Two traps, both hit while building this:

- `vsftpd_log_file=/dev/stdout` **does not work.** vsftpd reopens its log after
  dropping privileges and chrooting, by which point the `/proc/self/fd` symlink
  no longer resolves; it then refuses every connection with
  `500 OOPS: failed to open vsftpd log file` — which looks like an auth failure
  but happens before authentication. Logging goes through syslog instead.
- `seccomp_sandbox=NO` is required on Alpine, or transfers die immediately.

Passive mode only, ports 21000-21010, advertising `127.0.0.1`: both routes to
this server arrive over loopback, so one setting serves the VM and the physical
host alike.

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
