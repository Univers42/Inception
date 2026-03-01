# User Documentation — Inception

## What does this stack provide?

Inception deploys a complete WordPress website accessible over HTTPS:

| Service | Purpose |
|---------|---------|
| **NGINX** | Serves the site over TLS (port 443) |
| **WordPress** | Content management system (CMS) |
| **MariaDB** | Database engine storing all site content |

---

## Starting the project

```bash
make          # builds images, creates volumes, starts all containers
```

## Stopping the project

```bash
make down     # stops and removes containers (data is preserved)
```

## Restarting

```bash
make restart
```

---

## Accessing the website

| Page | URL |
|------|-----|
| **Front-end** | `https://dlesieur.42.fr` |
| **Admin panel** | `https://dlesieur.42.fr/wp-admin` |

> Your browser will warn about a self-signed certificate — this is expected.
> Accept the risk to proceed.

---

## Credentials

All passwords are stored in the `secrets/` directory at the project root:

| File | Contains |
|------|----------|
| `secrets/credentials.txt` | WordPress admin password (line 1), editor password (line 2) |
| `secrets/db_password.txt` | MariaDB application user password |
| `secrets/db_root_password.txt` | MariaDB root password |

Non-sensitive settings (domain, usernames, emails) are in `srcs/.env`.

### Default users

| User | Role | Username |
|------|------|----------|
| Administrator | Full control over WP | Value of `WP_ADMIN_USER` in `.env` |
| Editor | Can publish/edit posts | Value of `WP_USER` in `.env` |

---

## Checking that services are running

```bash
make status          # shows container status
make logs            # live tail of all service logs
docker compose -f srcs/docker-compose.yml ps   # alternative
```

All three containers should show **Up** (or **Up (healthy)**):

```
NAME        STATUS
nginx       Up (healthy)
wordpress   Up
mariadb     Up (healthy)
```

### Quick health checks

```bash
# TLS is working
curl -kI https://dlesieur.42.fr

# MariaDB responds
docker exec mariadb mysqladmin ping -h localhost --silent

# WordPress responds
docker exec wordpress wp --allow-root option get siteurl
```

---

## Where is my data?

| Data | Host path | Docker volume |
|------|-----------|---------------|
| Database files | `/home/dlesieur/data/mariadb` | `db_data` |
| WordPress files | `/home/dlesieur/data/wordpress` | `wp_data` |

Data persists across `make down` / `make up` cycles.
To **wipe everything** and start fresh: `make clean` or `make re`.
