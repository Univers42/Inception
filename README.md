*This project has been created as part of the 42 curriculum by dlesieur.*

# Inception

## Description

Inception is a system-administration project that builds a small, production-style web
infrastructure from scratch using **Docker Compose**. The stack runs three services, each
in its own container:

| Service | Role |
|---------|------|
| **NGINX** | TLS reverse-proxy (only entrypoint – port 443) |
| **WordPress + php-fpm** | Application server |
| **MariaDB** | Relational database |

All images are built locally from `alpine:3.20` — no pre-made images are pulled.
Persistent data (database + site files) lives in Docker named volumes mapped to
`/home/dlesieur/data` on the host. Credentials are managed via Docker secrets, never
hard-coded in Dockerfiles or committed to Git.

---

## Instructions

### Prerequisites

| Tool | Minimum version |
|------|----------------|
| Docker Engine | 24+ |
| Docker Compose (v2 plugin) | 2.20+ |
| GNU Make | 4+ |
| `sudo` access | for `/etc/hosts` and data dirs |

### Quick start

```bash
# 1. Clone the repository
git clone <repo-url> inception && cd inception

# 2. Create your secrets
mkdir -p secrets
echo 'YourDbPass!'          > secrets/db_password.txt
echo 'YourDbRootPass!'      > secrets/db_root_password.txt
printf 'WpAdminPass!\nWpEditorPass!' > secrets/credentials.txt

# 3. Copy and customise the environment file
cp .env.example srcs/.env
# Edit srcs/.env — set DOMAIN_NAME, usernames, emails, etc.

# 4. Build & launch
make          # equivalent to `make up`
```

The Makefile automatically:
- creates the host data directories (`/home/dlesieur/data/{mariadb,wordpress}`)
- adds the domain to `/etc/hosts` if missing
- builds the three Docker images and starts the stack

### Useful commands

| Command | Description |
|---------|-------------|
| `make up` | Build images & start containers |
| `make down` | Stop & remove containers |
| `make restart` | Restart all services |
| `make logs` | Follow live logs |
| `make status` | Show container status |
| `make clean` | Remove containers, volumes, images & host data |
| `make fclean` | `clean` + full Docker system prune |
| `make re` | `fclean` + `up` (full rebuild) |

### Accessing the site

Open **https://dlesieur.42.fr** in your browser (accept the self-signed certificate).

- **Site front-end:** `https://dlesieur.42.fr`
- **Admin panel:** `https://dlesieur.42.fr/wp-admin`

---

## Resources

### References

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose specification](https://docs.docker.com/compose/compose-file/)
- [Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Alpine Linux packages](https://pkgs.alpinelinux.org/packages)
- [NGINX TLS configuration](https://nginx.org/en/docs/http/configuring_https_servers.html)
- [WordPress CLI handbook](https://make.wordpress.org/cli/handbook/)
- [MariaDB Server documentation](https://mariadb.com/kb/en/documentation/)
- [Docker secrets](https://docs.docker.com/compose/how-tos/use-secrets/)
- [PID 1 and init in containers](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)

### AI usage

AI assistance (GitHub Copilot) was used for:
- Drafting boilerplate configuration files (nginx.conf, php-fpm pool, MariaDB tuning).
- Reviewing Dockerfile layer ordering and best-practice compliance.
- Generating documentation templates (this README, USER_DOC, DEV_DOC).

All generated content was reviewed, tested, and adapted to meet the specific project
constraints.

---

## Project description

### Why Docker?

Docker packages each service into an isolated, reproducible container.
Compared to installing everything on bare metal, this ensures that
the stack behaves identically on any machine and can be rebuilt from
scratch in seconds with `make re`.

### Virtual Machines vs Docker

| Aspect | Virtual Machine | Docker Container |
|--------|----------------|-----------------|
| **Isolation** | Full hardware-level (hypervisor) | Process-level (kernel namespaces + cgroups) |
| **Boot time** | Minutes | Seconds |
| **Resource overhead** | High (full guest OS) | Minimal (shares host kernel) |
| **Image size** | Gigabytes | Megabytes (Alpine ≈ 5 MB) |
| **Portability** | Limited to hypervisor | Runs anywhere Docker is installed |
| **Use case** | Running different OS kernels, strong security boundaries | Microservices, CI/CD, reproducible builds |

### Secrets vs Environment Variables

| Aspect | Environment Variables | Docker Secrets |
|--------|----------------------|---------------|
| **Visibility** | Visible in `docker inspect`, process table | Mounted as tmpfs files at `/run/secrets/` |
| **Persistence** | Stored in compose file or `.env` | Stored in separate files, referenced by compose |
| **Security** | Acceptable for non-sensitive config | Required for passwords, API keys, credentials |
| **Git safety** | `.env` in `.gitignore` | `secrets/` directory in `.gitignore` |

In this project, non-sensitive configuration (domain name, database name, usernames) is
passed via environment variables, while all passwords are stored exclusively in Docker
secrets.

### Docker Network vs Host Network

| Aspect | Docker Bridge Network | Host Network |
|--------|----------------------|-------------|
| **Isolation** | Containers have private IPs, communicate over a virtual bridge | Containers share the host's network stack |
| **Security** | Services are not exposed unless explicitly mapped | All container ports are directly on the host |
| **Service discovery** | Containers resolve each other by service name | Must use `localhost` + unique ports |
| **Port conflicts** | None (each container has its own IP) | Possible if services bind the same port |

This project uses a **bridge network** (`inception`) — only NGINX's port 443 is exposed;
WordPress and MariaDB are unreachable from outside the Docker network.

### Docker Volumes vs Bind Mounts

| Aspect | Named Volumes | Bind Mounts |
|--------|--------------|-------------|
| **Management** | Managed by Docker (`docker volume ls`) | Direct host path |
| **Portability** | Higher — volume name is abstracted | Lower — tied to host filesystem layout |
| **Permissions** | Docker handles ownership | Host file permissions apply |
| **Backup** | Via `docker run --volumes-from` or driver opts | Standard filesystem tools |

This project uses **named volumes** with `driver: local` and `device` options to store
data at a deterministic host path (`/home/dlesieur/data/`) while remaining proper Docker
volumes.
