# Developer Documentation — Inception

## Setting up the environment from scratch

### 1. Prerequisites

| Requirement | Notes |
|-------------|-------|
| Docker Engine ≥ 24 | `docker --version` |
| Docker Compose v2 plugin | `docker compose version` |
| GNU Make ≥ 4 | `make --version` |
| `sudo` access | needed for `/etc/hosts` and data directories |
| `openssl` (on host) | only needed if you want to inspect certs |

### 2. Create secrets

```bash
mkdir -p secrets

# Database passwords
echo 'YourDbUserPass'   > secrets/db_password.txt
echo 'YourDbRootPass'   > secrets/db_root_password.txt

# WordPress passwords (line 1 = admin, line 2 = editor)
printf 'WpAdminPass\nWpEditorPass' > secrets/credentials.txt
```

> **Security:** The `secrets/` directory is git-ignored. Never commit it.

### 3. Configure environment

```bash
cp .env.example srcs/.env
```

Edit `srcs/.env` and adjust:

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN_NAME` | Your 42 login domain | `dlesieur.42.fr` |
| `MYSQL_DATABASE` | WordPress DB name | `wordpress` |
| `MYSQL_USER` | DB application user | `wpuser` |
| `WP_ADMIN_USER` | WP admin login (**must not contain "admin"**) | `superuser` |
| `WP_ADMIN_EMAIL` | WP admin email | `superuser@dlesieur.42.fr` |
| `WP_USER` | Regular WP user | `editor` |
| `WP_USER_EMAIL` | Regular user email | `editor@dlesieur.42.fr` |

---

## Building and launching

```bash
make          # == make up
```

This runs:

1. `mkdir -p /home/dlesieur/data/{mariadb,wordpress}` — creates host volume directories
2. Adds `127.0.0.1 dlesieur.42.fr` to `/etc/hosts` if absent
3. `docker compose -f srcs/docker-compose.yml up -d --build` — builds all images and
   starts containers

### Build optimisation notes

- **Base image:** `alpine:3.20` (≈ 5 MB) — minimal download and layer size.
- **Single `RUN` layer** for all `apk add` — avoids intermediate layers.
- **`--no-cache`** flag — skips apk index caching inside the image.
- **`.dockerignore`** in each service context — prevents unnecessary files from entering
  the build context.
- **Layer ordering** — `COPY conf/` and `COPY tools/` come after `RUN apk add` so that
  config changes don't invalidate the package-installation cache.
- **`depends_on` with `condition: service_healthy`** for WordPress → MariaDB — avoids
  busy-wait retries when the DB isn't ready yet.

---

## Container management commands

| Command | Effect |
|---------|--------|
| `make up` | Build & start (detached) |
| `make down` | Stop & remove containers |
| `make stop` | Stop without removing |
| `make start` | Start stopped containers |
| `make restart` | Restart all |
| `make logs` | Tail all logs |
| `make status` | Show `docker compose ps` |
| `make clean` | Remove containers + volumes + images + host data |
| `make fclean` | `clean` + `docker system prune -af --volumes` |
| `make re` | Full teardown + rebuild |

### Exec into a container

```bash
docker exec -it nginx    sh
docker exec -it wordpress sh
docker exec -it mariadb   sh
```

### Manual DB access

```bash
docker exec -it mariadb mysql -u wpuser -p wordpress
# password prompt → enter content of secrets/db_password.txt
```

---

## Project structure

```
inception/
├── Makefile                          # Top-level build orchestrator
├── README.md                         # Project overview
├── USER_DOC.md                       # End-user documentation
├── DEV_DOC.md                        # This file
├── .env.example                      # Template for srcs/.env
├── .gitignore
├── secrets/                          # Docker secrets (git-ignored)
│   ├── credentials.txt               #   WP admin + editor passwords
│   ├── db_password.txt               #   MariaDB user password
│   └── db_root_password.txt          #   MariaDB root password
└── srcs/
    ├── .env                          # Runtime env vars (git-ignored)
    ├── docker-compose.yml            # Service definitions
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/my.cnf           # MariaDB server config
        │   └── tools/entrypoint.sh   # Init DB + exec mysqld
        ├── nginx/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/nginx.conf       # NGINX vhost template
        │   └── tools/entrypoint.sh   # Gen TLS cert + envsubst + exec nginx
        └── wordpress/
            ├── Dockerfile
            ├── .dockerignore
            ├── conf/www.conf         # php-fpm pool config
            └── tools/entrypoint.sh   # WP download/install + exec php-fpm
```

---

## Data persistence

| Docker volume | Host path | Contents |
|---------------|-----------|----------|
| `db_data` | `/home/dlesieur/data/mariadb` | MariaDB data directory |
| `wp_data` | `/home/dlesieur/data/wordpress` | WordPress core, themes, plugins, uploads |

Both are **Docker named volumes** using `driver: local` with `device` pointing to the
host directory. They survive `make down` / `make up` cycles.

### Inspecting volumes

```bash
docker volume ls
docker volume inspect srcs_db_data
docker volume inspect srcs_wp_data
```

### Wiping data

```bash
make clean    # removes volumes + host directories
make re       # clean + full rebuild
```

---

## Entrypoint design

Each container uses an entrypoint script that:

1. Reads secrets from `/run/secrets/*` (tmpfs, not persisted).
2. Performs **one-time initialisation** on first boot (create DB, download WP, generate
   TLS cert) guarded by an idempotent check (directory/file existence).
3. Calls `exec <daemon>` so the daemon becomes **PID 1** and receives signals properly.

No infinite loops, `tail -f`, `sleep infinity`, or background daemons are used.

---

## Service communication

```
        ┌──────────┐
Client ──► NGINX:443 │
        │ (TLS)    │
        └────┬─────┘
             │ fastcgi :9000
        ┌────▼──────────┐
        │ WordPress     │
        │ (php-fpm)     │
        └────┬──────────┘
             │ TCP :3306
        ┌────▼──────────┐
        │ MariaDB       │
        └───────────────┘
```

All containers are on the `inception` bridge network. Only NGINX exposes port 443 to the
host. WordPress and MariaDB are **not** reachable from outside the Docker network.
