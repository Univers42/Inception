# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

42 school project **Inception**: a three-container WordPress stack (NGINX / php-fpm+WordPress / MariaDB), every image hand-written `FROM alpine:3.23`, orchestrated by a root `Makefile` that drives `srcs/docker-compose.yml`. The grading rules from `en.subject.pdf` are encoded as an executable test suite (`tests/compliance.sh`) — **treat that suite as the spec**: most "obvious" refactors here will fail a numbered check.

`/home/dlesieur/goinfre/dlesieur-inception/Inception` and `/goinfre/dlesieur/dlesieur-inception/Inception` are the same directory (symlink).

## Commands

```bash
make               # == make up: setup (env/secrets/certs/hosts) + build + start
make build         # build images only
make down / restart / logs / status
make test          # compliance suite, static + runtime; exit code == number of failures
make test-deep     # + kills PID 1 in each container and cycles down/up (destructive to uptime, not data)
make bench         # build benchmarks (safe)
make bench-full    # + first-boot timing — WIPES /home/dlesieur/data
make run_wp        # waits for health, then a full WP report (core checksums, users, themes, DB, OPcache)
make trust         # install the local CA into system + Firefox/Chrome NSS stores
make clean         # this project's containers, volumes, images and host data
make fclean        # clean + machine-wide `docker system prune -af --volumes`
make re            # clean + up (keeps Docker build cache)
```

There is no per-check runner: `tests/compliance.sh` is one shell script whose checks are IDs `S01–S21` (static), `R01–R18` (runtime), `D01–D02` (deep). To iterate on one check, `sh tests/compliance.sh | grep -A2 S03` or copy that check's commands out of the script. Runtime checks silently skip when the stack is down.

Debugging:
```bash
docker exec wordpress wp --allow-root --path=/var/www/html <cmd>   # WP-CLI
docker exec -it mariadb mariadb -u wpuser -p wordpress             # pw = secrets/db_password.txt
docker logs <nginx|wordpress|mariadb>                              # entrypoints fail fast with [entrypoint] messages
```

## Architecture

Client → **nginx:443** (only published port, TLS 1.2/1.3 termination, serves static files itself from the WP volume mounted `:ro`) → FastCGI `wordpress:9000` → TCP `mariadb:3306`. All three on the `inception` bridge network, resolved by service name via Docker DNS.

Startup is gated by real healthchecks, not sleeps: mariadb is healthy only when the *application user* can connect over TCP, wordpress when php-fpm accepts a connection on 9000, nginx when HTTPS answers — chained with `depends_on: condition: service_healthy`. All healthchecks use `--start-interval=500ms` (Docker 25+) to cut dead time per hop.

Each service is a self-contained build context: `srcs/requirements/<svc>/{Dockerfile, conf/, tools/entrypoint.sh}`.

**Credential flow.** `make setup` generates `srcs/.env` (non-sensitive config only) and `secrets/*.txt` (random, never overwritten), and issues a local Root CA + server cert **on the host**. Compose mounts passwords and the server cert/key at `/run/secrets/*`; entrypoints read them from there. The CA private key never enters a container — `make trust` makes browsers trust that CA, so a container compromise must not leak it.

**Entrypoint contract** (all three follow it): validate env with `${VAR:?}` under `set -eu` → read and non-empty-check secrets → one-time init behind an idempotence guard → `exec <daemon>` as the final line so the daemon is PID 1.

Init guards: mariadb runs `mariadb-install-db` only if `/var/lib/mysql/mysql` is absent, then applies bootstrap SQL via `mariadbd --bootstrap` guarded by `/var/lib/mysql/.inception_init_done`; wordpress copies core from `/usr/src/wordpress` and installs only if `wp-config.php` is absent. **Consequence: editing `srcs/.env` or `secrets/` does not propagate to an initialised stack — `make clean && make` to re-apply.**

## Invariants that break the grade if violated

These are enforced by `tests/compliance.sh`; check the corresponding ID before changing anything nearby.

- **S03** — all three Dockerfiles pin the *same* base, and it must be the **penultimate stable** Alpine (checked live against Docker Hub, currently `alpine:3.23`). This target moves when Alpine releases; re-run `make test` near a defense date.
- **S06** — `tail -f`, `sleep infinity`, `while true`, `while :;`, `sleep <4+ digits>` are grepped for across Dockerfiles, entrypoints and compose. Never introduce one, even in a comment.
- **S18 / R10** — every entrypoint's last non-comment line is `exec <daemon>`; PID 1 must be `nginx` / `php-fpm84` / `mariadbd`.
- **S04 / S09** — no `:latest` anywhere; images are `<service>:inception`, containers named after their service.
- **S10 / R02 / S07** — exactly one published port, `443:443` on nginx. No `network_mode: host`, no `links:`.
- **S11 / R13** — two named volumes (`db_data`, `wp_data`) declared with `driver: local` + `device:` under `/home/dlesieur/data`; services must never bind-mount a host path directly.
- **S13 / S14 / S15** — no password-like content in Dockerfiles, tracked files, **or git history**. S15 scans `git log --all -p`; a committed credential stays failing until history is rewritten.
- **S17 / R08** — `WP_ADMIN_USER` must not contain "admin" (also enforced at boot by the wordpress entrypoint); exactly two WP users, one administrator.
- **S02** — `README.md`, `USER_DOC.md`, `DEV_DOC.md` must exist and README's first line must stay the italicised 42-curriculum sentence.
- **R14** — no `PASS`/`SECRET`/`TOKEN` environment variables on any container; passwords travel as secrets only.
- **R11** — strict isolation: no nginx binary in the app containers, no app daemons in nginx.

`DEV_DOC.md` is the canonical rationale document (design decisions, measured performance numbers, defense Q&A). Keep it in sync when changing behaviour — it is what the project is defended with.

## Gotchas worth knowing before editing

- **MariaDB bootstrap SQL must keep its leading `FLUSH PRIVILEGES;`** — `--bootstrap` has skip-grant-tables semantics, so `ALTER USER`/`GRANT` fail with error 1290 without it.
- **Don't redeclare `ssl_session_cache`** in the nginx vhost — Alpine's main `nginx.conf` already defines the SSL zone; duplicating it crash-loops nginx.
- The nginx entrypoint renders the vhost with `sed` substituting **only** `${DOMAIN_NAME}`, `${CERTS_CRT}`, `${CERTS_KEY}` — nginx runtime variables (`$uri`, `$fastcgi_script_name`, …) must survive untouched. `conf/nginx.conf` is copied to `default.conf.template`, not `default.conf`.
- The images deliberately ship less software than usual: no `wget` package (busybox handles HTTPS), no DB client in the WordPress image (the MariaDB wait probes with `php -r 'mysqli_connect(...)'`), and >100MB of unused MariaDB binaries are deleted in the install layer. Adding a package back for convenience regresses the size/build numbers in `DEV_DOC.md` §8.
- Build args `APK_CACHE_ID`, `DL_CACHE_ID`, `CACHE_BUST` exist for `tests/bench.sh` (honest cold vs. warm-cache scenarios) — keep them wired if you touch the package layers.
- Bumping PHP touches four coupled places: the wordpress Dockerfile (packages, `/etc/php84/*` paths, healthcheck), the `conf/www.conf` COPY target, `exec php-fpm84 -F` in the entrypoint, and `run_wp` in the Makefile.
- `LOGIN` and `DATA_DIR` are hardcoded near the top of the Makefile; `tests/compliance.sh` re-derives `LOGIN` by grepping the Makefile, so change them together.

## The documentation site (`srcs/requirements/wordpress/site/`)

The WordPress instance hosts this project's own documentation as a terminal-styled blog, fully baked into the image so a fresh clone reproduces it with no manual steps. `install.sh` runs from the wordpress entrypoint on **every** boot, **non-fatally** (a broken seed must never stop php-fpm): it re-syncs `theme/inception-terminal` and `plugin/inception-kit` from the image (image is the source of truth — local edits inside the volume are overwritten), then runs `seed.php` in a single `wp eval-file` process for activation, permalinks and content.

- Editing theme/plugin files requires a container recreate (`make up`), not `make restart`.
- Content pages/posts are seeded **once**, behind the `inception_site_seeded` option. To re-seed: `docker exec wordpress wp --allow-root option delete inception_site_seeded && make restart`. The seeder never touches content it did not create, so pages authored in wp-admin are safe.
- Shortcode gotcha: WordPress runs `wpautop`/texturize before shortcodes, so the kit registers its shortcodes in `no_texturize_shortcodes` and strips injected `<br/>` — without that, `--flags` inside `[cmd]` render as en-dashes.
