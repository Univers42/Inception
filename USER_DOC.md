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
Docker containers, built from scratch by this project (no ready-made images):

| Service | Purpose |
|---------|---------|
| **NGINX** | The web server. Serves the site over TLS on port 443 — the only door into the WordPress stack |
| **WordPress** | The content management system (CMS) you use to write and manage the site |
| **MariaDB** | The database that stores all site content (posts, users, settings) |
| **Static site** *(bonus)* | An independent, hand-written HTML/CSS/JS page — no PHP, no CMS — on port 8090 |

The first three services run in separate Docker containers and talk to each other over
a private Docker network; only NGINX's port (443) is reachable from outside that group.
The bonus static site is a fourth, fully independent container with its own port (8090)
— it shares nothing with WordPress or MariaDB. See §5c.

---

## 2. Prerequisites

Install these before doing anything else. All commands below are for Debian/Ubuntu —
adjust the package manager if you're on a different distribution.

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
2. **Build & start** — builds the three Docker images from their Dockerfiles and
   starts the containers.

The very first run takes roughly 15–30 seconds (downloading packages, building
images, initialising the database and WordPress). Expect one `sudo` password prompt
during step 1 (to add a line to `/etc/hosts`) — **this only happens on the first run**.

> If `sudo` fails with `sorry, you must have a tty to run sudo` (this happens when
> `make` is driven by another program instead of a normal interactive terminal), run
> this one line yourself in a real terminal first, then re-run `make`:
> ```bash
> echo "127.0.0.1 dlesieur.42.fr" | sudo tee -a /etc/hosts
> ```

When it finishes, check that all three containers are healthy:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Expected output — all three `Up ... (healthy)`:

```
NAME        STATUS
mariadb      Up (healthy)
wordpress    Up (healthy)
nginx        Up (healthy)
staticsite   Up (healthy)
```

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

| Name | Protocol | Host IP | Host Port | Guest IP | Guest Port |
|---|---|---|---|---|---|
| inception-https | TCP | (empty) | `8443` | (empty) | `443` |
| inception-static | TCP | (empty) | `8090` | (empty) | `8090` |

Or from the host's terminal (works while the VM is running):
```bash
VBoxManage controlvm "<vm-name>" natpf1 "inception-https,tcp,,8443,,443"
VBoxManage controlvm "<vm-name>" natpf1 "inception-static,tcp,,8090,,8090"
```

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
```
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
framework) running in its own container, on its own port, with no connection to
WordPress or MariaDB.

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
make status     # container status — all three should show "Up (healthy)"
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

| Data | Host path | Docker volume |
|---|---|---|
| Database | `/home/dlesieur/data/mariadb` | `inception_db_data` |
| Website files | `/home/dlesieur/data/wordpress` | `inception_wp_data` |

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
| **Adminer** (database UI) | `http://dlesieur.42.fr:8081` | server `mariadb`, user from `srcs/.env` (`MYSQL_USER`); for the password, read the file `secrets/db_password.txt` |
| **FTP** | `ftp://127.0.0.1:2121` from your host, or port 21 inside the VM | user from `srcs/.env` (`FTP_USER`); for the password, read the file `secrets/ftp_password.txt` |
| **Redis cache** | not exposed — it has no published port on purpose | none |
| **Database backups** | files in `/home/dlesieur/data/backups` | none |

**FTP must be used in passive mode.** Most clients (FileZilla, `lftp`, `curl`)
do this by default. Active mode cannot work through the VM's NAT.

```bash
# from the host
curl --ftp-pasv -u ftpuser:"$(cat secrets/ftp_password.txt)" ftp://127.0.0.1:2121/
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
