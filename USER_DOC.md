# User Documentation — Inception

This guide explains, in simple terms, how to use and administer the Inception stack.

## 1. What services does the stack provide?

Inception deploys a complete WordPress website served over HTTPS:

| Service | Purpose |
|---------|---------|
| **NGINX** | The web server. Serves the site over TLS on port 443 — the only door into the stack |
| **WordPress** | The content management system (CMS) you use to write and manage the site |
| **MariaDB** | The database that stores all site content (posts, users, settings) |

The three services run in separate Docker containers and talk to each other over a
private network. Only NGINX is reachable from your machine.

## 2. Starting and stopping the project

```bash
make            # first start: provisions everything, builds, launches (~20s)
make down       # stop and remove the containers — your data is preserved
make restart    # restart all services
```

After the first start, `make` brings the stack back in a few seconds.

## 3. Accessing the website and the administration panel

| Page | URL |
|------|-----|
| **Website** | `https://dlesieur.42.fr` |
| **Administration panel** | `https://dlesieur.42.fr/wp-admin` |

Log in to the admin panel with the administrator username from `srcs/.env`
(`WP_ADMIN_USER`, default `superuser`) and the password from
`secrets/credentials.txt` (first line).

> **About the certificate warning:** the site uses a certificate issued by a local
> certification authority. Either accept the browser warning once, or run
> `make trust` — it installs the CA into your system and browsers, and the padlock
> then shows as valid.

## 4. Locating and managing credentials

All passwords live in the `secrets/` directory at the project root. If you don't
create them yourself, **random ones are generated on first `make`**:

| File | Contains |
|------|----------|
| `secrets/credentials.txt` | WordPress **admin** password (line 1) and **editor** password (line 2) |
| `secrets/db_password.txt` | MariaDB application-user password |
| `secrets/db_root_password.txt` | MariaDB root password |

Read a password with, for example: `cat secrets/credentials.txt`

Non-sensitive settings (domain, usernames, emails, site title) are in `srcs/.env`.

### The two WordPress users

| User | Role | Username |
|------|------|----------|
| Administrator | Full control over the site | `WP_ADMIN_USER` in `srcs/.env` (default `superuser`) |
| Editor | Can write and publish posts | `WP_USER` in `srcs/.env` (default `editor`) |

**To change credentials:** edit the files in `secrets/` (and/or the names in
`srcs/.env`), then recreate the stack so they are applied everywhere:
`make clean && make`. (Passwords are baked into the database and WordPress on first
installation, so a simple restart is not enough.)

## 5. Checking that the services run correctly

```bash
make status     # container status — all three should show "Up (healthy)"
make logs       # live logs of all services
make test       # runs the full automated check suite
```

Expected `make status` output:

```
NAME        STATUS
nginx       Up (healthy)
wordpress   Up (healthy)
mariadb     Up (healthy)
```

Quick manual checks:

```bash
curl -kI https://dlesieur.42.fr                                  # TLS answers
docker exec mariadb mariadb-admin ping -h localhost --silent     # database alive
docker exec wordpress wp --allow-root option get siteurl         # WordPress alive
```

## 6. Where is my data?

| Data | Host path | Docker volume |
|------|-----------|---------------|
| Database | `/home/dlesieur/data/mariadb` | `inception_db_data` |
| Website files | `/home/dlesieur/data/wordpress` | `inception_wp_data` |

Data survives `make down` / `make up` cycles and machine reboots.
To **erase everything** and start fresh: `make clean` then `make` (or `make re`).
