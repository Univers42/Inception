# User Documentation — Inception

This guide is self-contained: follow it from a fresh clone, on a fresh machine (or
virtual machine), with no prior knowledge of the project, and you will end up with a
working WordPress website reachable over HTTPS. It covers installing what's needed,
starting the stack, finding your passwords, viewing the site from a browser (including
the extra step required when the project runs **inside a VM** and you want to browse
from the **host**), and day-to-day operation.

If you only ever read one file to use this project, read this one.

---

## 1. What you get

Inception deploys a complete WordPress website served over HTTPS, entirely inside
Docker containers, built from scratch by this project (no ready-made images).

**Eight containers run**, not three: the three the subject makes mandatory, plus five
bonus ones. Each is one container running exactly one long-lived program as PID 1 —
that is what makes it a *service* here, and the distinction matters, because two things
in this project look like services and are not (see "What is **not** a service" below).

### The eight services

| Service | Daemon running as PID 1 | Published to the host | Purpose |
|---|---|---|---|
| **nginx** | `nginx -g "daemon off;"` | **443** (TLS) | The web server, and the only door into the WordPress stack |
| **wordpress** | `php-fpm84 -F` | — (9000, network-internal) | The PHP processor running the CMS. Never talks to the host directly — nginx forwards to it |
| **mariadb** | `mariadbd --user=mysql` | — (3306, network-internal) | The database holding all site content (posts, users, settings) |
| **staticsite** *(bonus)* | `nginx -g "daemon off;"` | **8090** (plain HTTP) | A second, independent web server serving hand-written HTML/CSS/JS — no PHP, no CMS |
| **redis** *(bonus)* | `redis-server /etc/redis.conf` | — (6379, network-internal) | Object cache for WordPress, so repeated page loads skip database queries |
| **ftp** *(bonus)* | `pure-ftpd` | **21**, plus **21000–21010** for passive data | File access into the WordPress site files |
| **adminer** *(bonus)* | `php -S 0.0.0.0:8080` | **8080** (plain HTTP) | A web UI for browsing and editing the database |
| **dbbackup** *(bonus)* | `crond -f -l 8 -L /dev/stdout` | — (no port at all) | Scheduled database dumps; the daemon is cron itself |

Only the four ports in bold are reachable from outside. Everything else talks over a
private Docker bridge network named `inception`, where containers find each other by
service name (`mariadb`, `redis`, …) — never by IP address.

### What is **not** a service

Two things in this repository are easy to mistake for services, and neither is a
container in the running stack:

| Thing | What it actually is |
|---|---|
| **The documentation website** | Web pages, not a daemon. A custom theme, plugin and seed content living at `srcs/requirements/wordpress/site/`, baked into the WordPress image and installed into the CMS on boot. You reach it through the **nginx + wordpress** pair on port 443 like any other page of the site — it has no container, no port and no process of its own |
| **42ctl** | A command-line tool, not a daemon. It has a Dockerfile (`srcs/requirements/bonus/42ctl/`) but is deliberately absent from `docker-compose.yml`, because a CLI exits as soon as its command finishes, and a service here must run a real daemon as PID 1. It is built by `make 42ctl` and invoked one shot at a time by the `make vault-*` targets |

The general rule: **a port you browse to is not the same thing as a service.** A service
is a container with a daemon in it; a website is content that some service serves for you.

### Policies applied to every service

These are set identically across all eight, so there is one behaviour to remember rather
than eight:

| Policy | Value | What it means for you |
|---|---|---|
| Restart | `restart: unless-stopped` | A crashed container comes back by itself, and stays down after `make stop` until you ask for it |
| Health | a `HEALTHCHECK` in every one of the eight Dockerfiles | `make status` reports real health, not just "the process exists" |
| Network | one bridge network, `inception` | No container is on the host's network |
| PID 1 | the daemon itself, via `exec` | No `tail -f`, no `sleep infinity`, no supervisor — stopping the container signals the real program |
| Secrets | Docker secrets at `/run/secrets/*`, mode `0400` | No password is ever passed as an environment variable |

Startup order is enforced by health, not by guesswork — Compose waits for the
dependency to report *healthy* before starting the dependent:

- **nginx** waits for wordpress
- **wordpress** waits for mariadb and redis
- **adminer** waits for mariadb
- **dbbackup** waits for mariadb and wordpress
- **mariadb**, **redis**, **staticsite** and **ftp** wait for nothing — they have no dependencies

See §5c for the static site and §10 for the other bonus services.

---

## 2. Prerequisites

There are two ways to run this project. You can run it on a virtual machine — either
the one you were given or one you build yourself — or you can run it directly on the
machine you are sitting at. The setup below is identical either way; only the browser
step differs, and §5a and §5b cover both cases.

### Required tooling

Install these before doing anything else. All commands below are for Debian.
So, adjust the package manager if you're on a different distribution.

| Requirement | Check it's installed | Install if missing |
|---|---|---|
| Docker Engine | `docker --version` | `sudo apt update && sudo apt install -y docker.io` (or Docker's own install script) |
| Docker Compose v2 plugin | `docker compose version` | `sudo apt install -y docker-compose-plugin` |
| GNU Make | `make --version` | `sudo apt install -y make` |
| OpenSSL | `openssl version` | `sudo apt install -y openssl` |
| `sudo` access for your user | you'll be prompted for your password once | ask whoever administers the machine to add you to the `sudo` group |

You also need to be able to run `docker` as your user (either via `sudo`, or by being
in the `docker` group — check with `groups` — for these commands, if you're not in
the `docker` group, `docker` is auto-invoked through `sudo` by the Makefile only
where needed).

> **Note for Docker Desktop / rootless setups:** the Makefile assumes a standard Linux
> Docker Engine install where `docker` and `docker compose` work directly and only
> `/etc/hosts` editing needs `sudo`. If your `docker` commands themselves require
> `sudo`, run `sudo make` instead of `make`.

---

## 3. Get the project and start it

```bash
git clone <this-repository-url> inception
cd inception
make
```

`make` (with no arguments) does everything, in order:

1. **`setup`** — creates data directories, generates `srcs/.env`, generates random
   passwords under `secrets/`, adds an entry to `/etc/hosts`, and issues a local TLS
   certificate. All of this is described in detail in §4 below.
2. **Build & start** — builds the eight Docker images from their Dockerfiles and
   starts the eight containers.

The very first run takes roughly 15–30 seconds (downloading packages, building
images, initialising the database and WordPress). Expect one `sudo` password prompt
during step 1 (to add a line to `/etc/hosts`) — **this only happens on the first run**.

> If `sudo` fails with `sorry, you must have a tty to run sudo` (this happens when
> `make` is driven by another program instead of a normal interactive terminal), run
> this one line yourself in a real terminal first, then re-run `make`:
>
> ```bash
> echo "127.0.0.1 dlesieur.42.fr" | sudo tee -a /etc/hosts
> ```

When it finishes, check that all eight containers are healthy:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Expected output — all eight `Up ... (healthy)`, since every image carries a healthcheck:

```text
NAME         STATUS               PORTS
adminer      Up (healthy)         0.0.0.0:8080->8080/tcp
dbbackup     Up (healthy)
ftp          Up (healthy)         0.0.0.0:21->21/tcp, 0.0.0.0:21000-21010->21000-21010/tcp
mariadb      Up (healthy)         3306/tcp
nginx        Up (healthy)         0.0.0.0:443->443/tcp
redis        Up (healthy)         6379/tcp
staticsite   Up (healthy)         0.0.0.0:8090->8090/tcp
wordpress    Up (healthy)         9000/tcp
```

A port shown without an `0.0.0.0:...->` prefix (mariadb, redis, wordpress) is
network-internal — the container listens on it, but the host cannot reach it. That is
deliberate, not a missing rule.

(`make status` does the same thing.)

---

## 4. What `make` set up for you (and where to find it)

Nothing needs to exist before the first `make` — everything below is created
automatically, **only if missing** (so re-running `make` never overwrites your data
or passwords).

| What | Where | Contents |
|---|---|---|
| Site configuration | `srcs/.env` | Domain name, database name, WordPress usernames/emails — non-secret |
| WordPress admin + editor passwords | `secrets/credentials.txt` | Line 1 = admin password, line 2 = editor password |
| Database application-user password | `secrets/db_password.txt` | Random, used by WordPress to connect to MariaDB |
| Database root password | `secrets/db_root_password.txt` | Random, MariaDB root account |
| TLS certificate authority | `secrets/ca.key`, `secrets/ca.crt` | A local Certificate Authority created just for this project |
| TLS server certificate | `secrets/server.key`, `secrets/server.crt` | Certificate for your domain, signed by the local CA above |
| `/etc/hosts` entry | (system file) | `127.0.0.1 dlesieur.42.fr`, so that domain resolves to this machine |

The domain name defaults to **`dlesieur.42.fr`** — it comes from the `LOGIN` variable
at the top of the `Makefile` (`LOGIN = dlesieur`), not from your actual Linux username.
If you're running this on a machine where you are *not* `dlesieur` (e.g. you cloned
this repo under your own account), either:

- keep using `dlesieur.42.fr` as-is (it will still work — it's just a name, resolved
  locally via `/etc/hosts`), or
- edit `LOGIN` in the `Makefile` to your own username before the first `make`, so the
  domain, `/etc/hosts` entry and certificate all use it instead.

If you want a different domain without touching `LOGIN`, edit `DOMAIN_NAME` in
`srcs/.env` before running `make` again — the certificate is automatically re-issued
for the new name (but you'll then need to add *that* name to `/etc/hosts` yourself,
since the automatic `/etc/hosts` line is tied to `LOGIN`, not to `DOMAIN_NAME`).

To read a password:

```bash
cat secrets/credentials.txt          # line 1 = WP admin, line 2 = WP editor
cat secrets/db_password.txt
cat secrets/db_root_password.txt
```

**To change any password or username:** edit the relevant file in `secrets/` (or the
username/email fields in `srcs/.env`), then rebuild from scratch so the new values are
actually applied to the database and WordPress:

```bash
make clean && make
```

(A plain restart is *not* enough — WordPress and MariaDB only read these values the
very first time they initialise their data.)

---

## 5. Viewing the website in your browser

### 5a. Running directly on the machine you're browsing from

Just open your browser at the site and admin URLs (see §4 if you changed `LOGIN` in
the `Makefile` — the domain would then be `<your-login>.42.fr` instead):

| Page | URL |
|---|---|
| **Website** | `https://dlesieur.42.fr` |
| **Admin panel** | `https://dlesieur.42.fr/wp-admin` |
| **Bonus static site** | `http://dlesieur.42.fr:8090` (see §5c) |

Log in with the admin username from `srcs/.env` (`WP_ADMIN_USER`) and the password
from `secrets/credentials.txt` (first line).

You'll get a certificate warning (`NET::ERR_CERT_AUTHORITY_INVALID` / "Your connection
is not private") the first time — this is expected, because the certificate is issued
by a *local* certificate authority your browser doesn't know yet, not a public one.
Either:

- click through the warning once ("Advanced" → "Proceed anyway"), or
- run `make trust` — it installs the local CA into your system and browser trust
  stores (covers Firefox and Chromium, including their Snap/Flatpak variants), so the
  padlock shows as fully valid afterwards. Close and reopen your browser after running it.

### 5b. Running **inside a virtual machine**, viewed from the **host**

This is a common setup: Inception runs inside a VM (VirtualBox, in this case), but you
want to see the website in a browser on your physical host machine. By default a VM's
network is isolated from the host, so this needs a NAT port-forwarding rule — **and
that's all it needs**. `wp-config.php` is written (§4/§6 in `DEV_DOC.md`) to serve the
site correctly whether it's reached as `dlesieur.42.fr`, `localhost`, or `127.0.0.1` —
so once the port is forwarded, `https://localhost:<host-port>` just works. No
`/etc/hosts` edit on the host is required, on either OS — useful when you don't have
admin rights on the host machine (e.g. a shared lab computer), since `VBoxManage`/the
VirtualBox GUI configures NAT rules as your normal user, with no `sudo`/admin needed.

**Step 1 — add a port-forwarding rule.**
VirtualBox → select the VM → *Settings* → *Network* → *Adapter 1* → *Advanced* →
*Port Forwarding*, add a rule (host port is your choice, e.g. `8443`):

Four services publish a port, so there are five rules — add only the ones you actually
want to reach from the host. The website is the one that matters; the rest are optional.

| Name | Protocol | Host IP | Host Port | Guest IP | Guest Port | For |
|---|---|---|---|---|---|---|
| inception-https | TCP | (empty) | `8443` | (empty) | `443` | the website |
| inception-static | TCP | (empty) | `8090` | (empty) | `8090` | the static site |
| inception-adminer | TCP | (empty) | `8080` | (empty) | `8080` | the database UI |
| inception-ftp | TCP | (empty) | `21` | (empty) | `21` | FTP control |
| inception-ftp-pasv | TCP | (empty) | `21000-21010` | (empty) | `21000-21010` | FTP passive data |

Or from the host's terminal (works while the VM is running):

```bash
VBoxManage controlvm "<vm-name>" natpf1 "inception-https,tcp,,8443,,443"
VBoxManage controlvm "<vm-name>" natpf1 "inception-static,tcp,,8090,,8090"
VBoxManage controlvm "<vm-name>" natpf1 "inception-adminer,tcp,,8080,,8080"
VBoxManage controlvm "<vm-name>" natpf1 "inception-ftp,tcp,,21,,21"
```

Only the website's rule remaps the port (guest `443` → host `8443`, because binding
host port 443 needs root). Keep the others identical on both sides — in particular the
FTP passive range, which must not be remapped: see §10.

**Step 2 — browse from the host, using `localhost` (not the domain):**

| Page | URL from the host browser |
|---|---|
| Website | `https://localhost:8443` |
| Admin panel | `https://localhost:8443/wp-admin` |
| Bonus static site | `http://localhost:8090` |

(Swap `localhost` for `127.0.0.1` if you prefer — both work identically; the TLS
certificate and `wp-config.php` cover both.)

The certificate warning from §5a still applies — the local CA is trusted *inside the
VM* only (`make trust` runs there), not on the host, so expect the warning in the host
browser unless you also import `secrets/ca.crt` into the host's trust store.

**If you *do* have admin rights on the host** and specifically want the real
`dlesieur.42.fr` domain to resolve there too (e.g. to demo the exact grading URL),
you can additionally add a host-side `/etc/hosts` entry — see the box below — but it
is optional; everything in this section already works without it.

<details>
<summary>Optional: also making <code>dlesieur.42.fr</code> itself resolve on the host</summary>

Add to the **host's own** hosts file (`/etc/hosts` on Linux/macOS,
`C:\Windows\System32\drivers\etc\hosts` on Windows, edited as administrator):

```text
127.0.0.1   dlesieur.42.fr
```

Or, for a Bridged-Adapter VM (own LAN IP, no port forwarding needed), use the VM's
real IP instead of `127.0.0.1` and skip the port in the URL below.

Then browse `https://dlesieur.42.fr:8443` from the host.
</details>

> If you just want a quick sanity check that the server is reachable, `curl` works the
> same way, e.g. from the host: `curl -k https://dlesieur.42.fr:8443` should return HTML.

### 5c. Bonus: the static website (no WordPress, no PHP)

Separate from everything above, the stack also ships a **bonus service**: a small
self-contained static website (plain HTML/CSS/vanilla JavaScript, no PHP, no
framework) running in its own container, on its own port.

This one really is a service and not just a page — unlike the documentation website of
§1, it has its own `nginx` daemon and its own container. It sits on the `inception`
network like everything else, but it neither queries MariaDB nor shares the WordPress
volume, so nothing it serves depends on the CMS being up.

| Page | URL |
|---|---|
| **Bonus static site** | `http://dlesieur.42.fr:8090` |

It's plain HTTP (no TLS) since it carries no credentials or sensitive data — just
static files. If you're viewing from a VM host (§5b), the same port-forwarding /
`/etc/hosts` steps apply, just forwarding to guest port `8090` instead of `443`
(and using `http://`, not `https://`).

---

## 6. Checking that the services are running correctly

```bash
make status     # container status — all eight should show "Up (healthy)"
make logs       # live logs of all services (Ctrl+C to stop watching)
make test       # runs the full automated compliance/health check suite
```

Quick manual checks (run these inside the VM / on the machine running `make`):

```bash
curl -kI https://dlesieur.42.fr                                  # TLS answers
docker exec mariadb mariadb-admin ping -h localhost --silent     # database alive
docker exec wordpress wp --allow-root option get siteurl         # WordPress alive
```

`make run_wp` prints a full guided health report (WordPress version, users, active
theme, PHP/OPcache status, DB connection) and opens the site in your default browser.

---

## 7. Starting, stopping, and restarting

```bash
make            # first run: full setup + build + start; later runs: just start
make down       # stop and remove the containers — your data is preserved
make stop       # stop containers without removing them
make start      # start previously-stopped containers
make restart    # restart all services
```

After the first run, `make` brings the stack back up in a few seconds — it does not
rebuild or regenerate anything that already exists.

---

## 8. Where is my data, and how do I wipe it?

There are three volumes, each a named Docker volume bound to a directory under
`/home/dlesieur/data`:

| Data | Host path | Docker volume | Used by |
|---|---|---|---|
| Database | `/home/dlesieur/data/mariadb` | `inception_db_data` | mariadb |
| Website files | `/home/dlesieur/data/wordpress` | `inception_wp_data` | wordpress (read-write), nginx (**read-only**), ftp (read-write) |
| Database backups | `/home/dlesieur/data/backups` | `inception_backup_data` | dbbackup |

Three services share the WordPress volume, which is why a file uploaded over FTP shows
up on the website immediately — it is the same directory. nginx mounts it read-only: it
serves those files but can never modify them.

Data survives `make down` / `make up` cycles and reboots.

To **erase everything** (containers, images, volumes, and this host data) and start
completely fresh:

```bash
make clean && make
```

(or `make re`, which does the same thing). This does **not** touch `secrets/` or
`srcs/.env` — delete those yourself first if you also want brand-new random
passwords and a freshly issued certificate.

---

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| `sudo: sorry, you must have a tty to run sudo` during `make` | Run the `/etc/hosts` line from §3 yourself in an interactive terminal, then re-run `make` |
| Browser can't reach the site at all (VM setup) | Re-check §5b — port forwarding rule and the host's `/etc/hosts` entry are the two most commonly missed steps |
| Browser shows a certificate warning | Expected with the local CA — click through it once, or run `make trust` (only trusts it on the machine `make trust` was run on) |
| A container keeps restarting | `docker logs <container-name>` — entrypoints print a clear error message on failure |
| Changed a password in `secrets/` but the site still uses the old one | Passwords are only read on first initialisation — `make clean && make` to apply new ones |
| `docker compose` errors about a missing secret file | Don't run `docker compose` directly for the first setup — always go through `make` (or run `make setup` first), which creates the `secrets/` files |
| `make trust` fails to find a browser profile | Fully quit the browser (all windows) before running it, then reopen after |

For architecture details, performance notes, and a defense/Q&A style deep dive, see
`DEV_DOC.md`.

---

## 10. Bonus services

Five extra services run alongside the website. All are started and stopped by
the same `make` commands — there is nothing separate to launch.

| Service | How you reach it | Credentials |
|---|---|---|
| **Static showcase site** | `http://dlesieur.42.fr:8090` | none |
| **Adminer** (database UI) | `http://dlesieur.42.fr:8080` | server `mariadb`, user from `srcs/.env` (`MYSQL_USER`); for the password, read the file `secrets/db_password.txt` |
| **FTP** | `ftp://127.0.0.1:21` | user from `srcs/.env` (`FTP_USER`); for the password, read the file `secrets/ftp_password.txt` |
| **Redis cache** | not exposed — it has no published port on purpose | none |
| **Database backups** | files in `/home/dlesieur/data/backups` | none |

**FTP must be used in passive mode.** Most clients (FileZilla, `lftp`, `curl`)
do this by default. Active mode cannot work through the VM's NAT.

The passive data ports (`21000–21010`) are published one-to-one on purpose: passive
mode tells the client which port to open next, so remapping them would advertise a port
number that no longer leads anywhere. `FTP_PASV_ADDRESS` in `srcs/.env` is `127.0.0.1`
— correct both inside the VM and from the host through VirtualBox NAT, since both
routes reach the server over loopback.

```bash
curl --ftp-pasv -u ftpuser:"$(cat secrets/ftp_password.txt)" ftp://127.0.0.1:21/
```

### Your backups

A dump is taken when the stack starts and then every 6 hours (`BACKUP_CRON` in
`srcs/.env`), keeping the newest 7 (`BACKUP_KEEP`).

```bash
ls -lh /home/dlesieur/data/backups          # what you have
docker exec dbbackup backup.sh              # take one right now
docker exec dbbackup restore.sh             # restore the most recent
docker exec dbbackup restore.sh /backups/wordpress-20260828-123429.sql.gz
```

Restoring overwrites the current database with the contents of the dump. If you
want to be sure a backup is good without restoring it, `gzip -t` it — that is
exactly what the container's healthcheck does.

### Is the cache actually working?

```bash
docker exec wordpress wp --allow-root --path=/var/www/html redis status
```

Look for `Status: Connected` and `Drop-in: Valid`. `docker exec redis
redis-cli dbsize` shows the number of cached entries, which climbs as pages are
visited.
