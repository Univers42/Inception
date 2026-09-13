# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in
this repository.

## What this is

42 "Inception": a hand-built Docker Compose infrastructure. Three mandatory services
(nginx / WordPress+php-fpm / MariaDB), each built from its own Dockerfile `FROM alpine:3.23`
— no pre-made service images. Bonus compose services: staticsite, redis, ftp, adminer,
dbbackup, and the "lab" (`web` + `api`). Two more bonus images are CLIs and deliberately NOT
compose services, because a CLI cannot be an honest PID-1 daemon: `42ctl` and `nodetool`.
`srcs/requirements/bonus/app/` is tracked but referenced by nothing. The subject rules are
non-negotiable and are encoded as an executable test suite; treat a `make test` failure as a spec
violation, not a flaky test.

## Commands

```bash
make                # == make up : setup + docker compose up -d --build
make build          # provision + build images only
make down/stop/start/restart
make logs / make status
make test           # hellish-check, then tests/compliance.sh — static + runtime, no sudo, ~1 min
make test-deep      # + kills PID 1 in each container, cycles down/up, checks persistence
make test-lab       # tests/lab.sh against the running web + api (LAB_ARGS=--deep for more)
make hellish-check  # hellish is the interpreter on the host, in every shebang and every container
make hellish-fetch  # stage the static hellish release binary in srcs/shell/ (checksum verified)
make bench          # honest cold-build benchmark   (bench-full also wipes project data)
make run_wp         # WP health report (core checksums, users, themes, DB, OPcache) + opens the site
make trust          # install the local CA into system + Firefox/Chrome NSS stores
make clean          # remove this project's containers, volumes, images and host data
make fclean         # clean + machine-wide `docker system prune -af --volumes`
make re             # clean + up
make snapshot       # refresh the lab's JSON snapshots from the running API; make re-web ships them
make lock           # re-resolve web/api lockfiles inside nodetool (make npm-web NPM="…" for any npm)
```

Running tests while iterating: `hellish tests/compliance.sh --no-clone` (or `NO_CLONE=1`) skips
the preliminary checks that clone the repo over the network. There is **no per-check
filter** — checks are grouped `[P]` preliminary / `[S]` static / `[R]` runtime, and the
`[R]` block auto-skips when the stack is not running. `bench.sh` takes `--with-boot`.

Direct container access:

```bash
docker exec wordpress wp --allow-root --path=/var/www/html <cmd>
docker exec -it mariadb mariadb -u root -p"$(cat secrets/db_root_password.txt)" wordpress
docker compose -f srcs/docker-compose.yml <cmd>     # what the Makefile wraps
```

Do not invoke `docker compose` for a first run — `make setup` must generate the secrets
and certs first.

## Architecture

**The Makefile is the only orchestrator.** `make up` runs `setup` then
`docker compose -f srcs/docker-compose.yml up -d --build`. `setup` generates every missing
piece and **never overwrites**: host data dirs under `$(DATA_DIR)/{mariadb,wordpress,backups}`
(default `/home/dlesieur/data`), `srcs/.env` from `.env.example` (login substituted), random
`secrets/*.txt` (including `api_db_password.txt` for the lab), the `/etc/hosts` entry, a host-side
Root CA + server cert (`certs` target), and the static hellish binary at `srcs/shell/hellish`.
To use custom passwords, create the `secrets/*.txt` files before the first `make`.

**Service layout.** Compose project name `inception`. Each service is a self-contained context:
`srcs/requirements/<svc>/{Dockerfile, conf/, tools/entrypoint.sh}` (bonus under
`srcs/requirements/bonus/<svc>/`). Images are named `<svc>:inception`, containers `<svc>`.
All on the `inception` bridge network, resolving each other by service name. Only nginx
publishes a port (443).

**Entrypoint pattern — every service follows it:**

1. `set -eu`, `${VAR:?}` validation, secrets read from `/run/secrets/*`, checked non-empty.
2. One-time init behind an idempotence guard (MariaDB: marker = `/var/lib/mysql/mysql` +
   post-success marker; WordPress: `wp-config.php` existence). MariaDB init uses
   `mariadbd --bootstrap` (SQL on stdin, no temp server) and the bootstrap SQL **must** start
   with `FLUSH PRIVILEGES;` or `ALTER USER`/`GRANT` fail with error 1290.
3. Bounded wait loops only. `tail -f`, `sleep infinity`, `while true`, bare shells and process
   supervisors are forbidden by the subject and grepped for by `compliance.sh` (S06/S23).
4. Last line is `exec <daemon>` so the daemon is PID 1 (checked by R10/S18).

**Consequence of the guards:** changing a secret or an `.env` value after first boot does
**not** propagate — the DB and `wp-config.php` keep first-boot values. Re-init with
`make clean && make`. The WordPress entrypoint does separately re-sync `DB_PASSWORD`, user
passwords, and Redis settings into an existing `wp-config.php` on each boot.

**Secrets.** `secrets/*.txt` → Docker secrets → `/run/secrets/<name>` (mode 0400), never env
vars. `credentials.txt` = line 1 WP admin password, line 2 editor password. The CA **private
key never enters a container** — nginx receives only the server cert + key.
`secrets/` and `srcs/.env` are git-ignored; `compliance.sh` greps tracked files *and the
full git history* for credential-shaped strings (S14/S15/S24), and keeps a literal
`password = ...` out of tracked docs.

**nginx** (`conf/nginx.conf`, rendered by `sed` from a `.template` — only `${DOMAIN_NAME}`,
`${CERTS_CRT}`, `${CERTS_KEY}` are substituted): `ssl_protocols TLSv1.2 TLSv1.3` only;
`fastcgi_pass` goes through `set $upstream_wordpress wordpress:9000;` + `resolver 127.0.0.11`
so nginx re-resolves WordPress's IP per request (a literal `fastcgi_pass wordpress:9000;`
caches the IP and 502s after the wordpress container is recreated).

**WordPress** `wp-config.php` (heredoc in the entrypoint) derives `WP_HOME`/`WP_SITEURL`
dynamically from `$_SERVER['HTTP_HOST']` against a whitelist (`DOMAIN_NAME`, `localhost`,
`127.0.0.1` — the cert's SANs), falling back to the canonical domain. This is deliberate,
so the site works both via `https://dlesieur.42.fr` and a NAT-forwarded `localhost:port`.

**Volumes** are named volumes with `driver: local` + a `device:` bind option into
`/home/dlesieur/data/...` — this satisfies "named volume" and "data under /home/login/data"
at once. Services never bind-mount a host path directly.

## hellish is the only shell (unusual — read before touching the Makefile)

Every script under `srcs/` and `tests/` has a `#!/bin/hellish` shebang, and `make test` runs
`hellish-check` first, which FAILS unless every tracked `.sh` declares it. New scripts must too.

- **`SCRIPT_SH`** — interprets the Make recipes (`SHELL := $(SCRIPT_SH)`) and `tests/*.sh`. The
  candidates are hellish in the system paths, then `command -v hellish` (on a 42 machine,
  `~/.local/bin/hellish`); each is probed with `tests/launcher_probe.sh`. There is no fallback:
  without a working hellish the Makefile stops with `no usable hellish interpreter`. Override with
  `make … SCRIPT_SH=/path`.
- **`INCEPTION_SHELL`** (default `SCRIPT_SH`) — the binary `setup` copies to `srcs/shell/hellish`.
  It must be **statically linked** (the images are Alpine/musl); a dynamic one is refused, and
  `make hellish-fetch` stages the pinned `HELLISH_VERSION` release instead. Every Dockerfile's last
  step links both `/bin/hellish` and `/bin/sh` to it, via the `shell` additional build context in
  `docker-compose.yml`. Only `srcs/shell/README.md` is tracked.

## Host-only overrides (git-ignored, both have a tracked `.example`)

- `srcs/local.mk` — `DATA_DIR` and `DOCKER_CONFIG`. On a 42 workstation `$HOME` is small and
  sgoinfre refuses the chown MariaDB needs, so volumes go under `/goinfre/dlesieur/…`.
- `srcs/docker-compose.local.yml` — port remaps for a rootless Docker daemon that cannot bind 443;
  `HTTPS_PORT` and `SITE_URL` follow it automatically.

Absent on the VM and the evaluation machine, where nothing changes.

## 42ctl and the vault (bonus)

`make 42ctl` builds `42ctl:inception` from `C42_REPO@C42_REF` (GitHub, not the sibling checkout),
configured in `srcs/requirements/bonus/42ctl/conf/42ctl.conf` — tracked, so endpoints only, never
a credential. `C42_RUN` runs it one shot as the caller's uid with `C42_HOME` (default
`~/.config/42ctl`) mounted at `/config` and `FT_CONFIG`/`FT_KEYSTORE` pointed there; without that
mount every run forgets the identity and login of the previous one.

```bash
make vault-init                                   # once per machine: keys init
make vault-signup EMAIL=you@example.com           # once per person
make vault-login  EMAIL=you@example.com TENANT=yourname
make vault-status                                 # config show + auth status
make vault-push                                   # scans .42ctl/project.json patterns + secrets/**
make vault-pull [APPLY=1]                         # dry run unless APPLY=1
```

The targets call 42ctl by flag name, so a renamed 42ctl flag breaks them: re-check them against
`42ctl help commands` (or `42ctl <verb> --help` on older builds) after bumping `C42_REF`.

## Deliverables that must keep their shape

`README.md`, `USER_DOC.md`, `DEV_DOC.md` are graded. `compliance.sh` S25/S26 enforce required
sections (README: Description/Instructions/Resources, the AI-usage note, and four named
comparisons; USER/DEV docs: specific topics). Don't drop a section when editing.
**`DEV_DOC.md` is the deep reference** — architecture, defense Q&A, performance measurements,
per-bonus rationale, and a "where to touch for a given change" table. Read it before larger
changes.

## Documentation website

`srcs/requirements/wordpress/site/` (custom theme + plugin + seed content) is baked into the
WordPress image. `tools/entrypoint.sh` calls `site/install.sh` **non-fatally**: it re-syncs
the theme/plugin from the repo on every boot (repo is source of truth) and runs `seed.php`
once, guarded by the `inception_site_seeded` WP option. Re-seed with
`docker exec wordpress wp --allow-root option delete inception_site_seeded && make restart`.

## Other

- `vendor/scripts/` is a git submodule (`Univers42/scripts`) of general dev utilities — not
  part of the build. `strip_comments.py` there is used to strip comments from sources.
- This repo is also `42ctl`'s QA fixture (`../42ctl/qa/fixtures/inception`, pinned by commit).
- `alpine:3.23` is "penultimate stable" *as of now* — this moves with Alpine releases and
  `compliance.sh` S03 verifies it live against Docker Hub. Expect to bump the pin (identically
  in all Dockerfiles) near a defense.
- End git commit messages with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
