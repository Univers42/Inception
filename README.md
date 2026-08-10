*This project has been created as part of the 42 curriculum by dlesieur.*

# Inception

## Description

Inception is a system-administration project that builds a small, production-style web
infrastructure from scratch using **Docker Compose**. The goal is to understand how
containerised services are built, isolated, connected, and persisted — by writing every
Dockerfile by hand instead of pulling ready-made images.

The stack runs three services, each in its own dedicated container:

| Service | Role |
|---------|------|
| **NGINX** | TLS termination — the only entrypoint, port 443, TLSv1.2/1.3 only |
| **WordPress + php-fpm 8.4** | Application server (FastCGI, no web server inside) |
| **MariaDB 11.4** | Relational database (no web server inside) |

Key properties:

- All images are built locally from **`alpine:3.23`** — the *penultimate stable* Alpine
  release, as the subject requires. No service image is ever pulled.
- Persistent data (database + site files) lives in **Docker named volumes** stored under
  `/home/dlesieur/data` on the host.
- All credentials are delivered through **Docker secrets** — never hard-coded, never in
  environment variables, never committed to Git.
- The TLS certificate is issued by a **local CA on the host**; the CA private key never
  enters any container.
- The repository ships its own **compliance test suite** (`make test`) that maps
  one-to-one to the subject's rules, and **benchmarks** (`make bench`): a fresh clone
  reaches a live site in ~20s, a rebuilt stack in under 10s.

---

## Instructions

### Prerequisites

| Tool | Minimum version |
|------|----------------|
| Docker Engine | 24+ (25+ recommended for fast startup healthchecks) |
| Docker Compose (v2 plugin) | 2.20+ |
| GNU Make | 4+ |
| `openssl` (host) | secrets + TLS certificate generation |
| `sudo` access | for `/etc/hosts` and data-dir cleanup |

### Quick start

```bash
git clone <repo-url> inception && cd inception
make          # that's it — equivalent to `make up`
```

`make` runs a `setup` step that provisions everything that is missing, then builds and
starts the stack:

- creates the host data directories (`/home/dlesieur/data/{mariadb,wordpress}`)
- generates `srcs/.env` from `.env.example` (edit it to customise names/emails)
- generates **random passwords** into `secrets/` (never overwrites existing ones)
- adds `dlesieur.42.fr` to `/etc/hosts` if missing
- creates a local Root CA and issues the server certificate **on the host**
- builds the three Docker images and starts the stack

To use your own passwords instead of generated ones, create the files before `make`:

```bash
mkdir -p secrets
echo 'YourDbPass'      > secrets/db_password.txt
echo 'YourDbRootPass'  > secrets/db_root_password.txt
printf 'WpAdminPass\nWpEditorPass\n' > secrets/credentials.txt   # line 1 admin, line 2 editor
```

### Useful commands

| Command | Description |
|---------|-------------|
| `make up` | Provision + build images + start containers |
| `make down` | Stop & remove containers (data preserved) |
| `make restart` | Restart all services |
| `make logs` / `make status` | Follow logs / show container status |
| `make test` | Run the subject-compliance test suite (static + runtime) |
| `make test-deep` | Same + crash-restart and persistence tests |
| `make bench` / `make bench-full` | Build (+ boot) benchmarks |
| `make run_wp` | Full WordPress health report (versions, users, themes, DB) |
| `make trust` | Trust the local CA system-wide → clean padlock in browsers |
| `make clean` | Remove this project's containers, volumes, images & host data |
| `make fclean` | `clean` + full Docker system prune (machine-wide!) |
| `make re` | `clean` + `up` — full project rebuild, Docker build cache kept |

### Accessing the site

- **Site front-end:** `https://dlesieur.42.fr`
- **Admin panel:** `https://dlesieur.42.fr/wp-admin`

The certificate is issued by a local CA. Either accept the browser warning once, or run
`make trust` to install the CA into the system/browser trust stores.

---

## Resources

### References

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose specification](https://docs.docker.com/compose/compose-file/)
- [Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [BuildKit cache mounts](https://docs.docker.com/build/cache/optimize/)
- [Alpine Linux packages](https://pkgs.alpinelinux.org/packages)
- [NGINX TLS configuration](https://nginx.org/en/docs/http/configuring_https_servers.html)
- [WordPress CLI handbook](https://make.wordpress.org/cli/handbook/)
- [MariaDB Server documentation](https://mariadb.com/kb/en/documentation/)
- [Docker secrets](https://docs.docker.com/compose/how-tos/use-secrets/)
- [PID 1 and init in containers](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)

### AI usage

AI assistance was used for the following tasks:

- Drafting boilerplate configuration files (nginx vhost, php-fpm pool, MariaDB tuning).
- Auditing the project against the subject PDF and finding compliance gaps and bugs
  (e.g., a first-boot bug that produced a theme-less blank site).
- Writing the compliance test suite (`tests/compliance.sh`) and the benchmark harness
  (`tests/bench.sh`).
- Performance engineering of the build and boot paths (multi-stage builds, BuildKit
  cache mounts, image trimming, healthcheck tuning) with before/after measurements.
- Generating and maintaining the documentation (this README, USER_DOC, DEV_DOC).

All generated content was reviewed, tested against the running stack, and adapted to the
project constraints. The design decisions and their rationale are documented in
`DEV_DOC.md` so they can be explained and defended without AI assistance.

---

## Project description

### Use of Docker and sources included

Everything needed to build the infrastructure lives in this repository: a root
`Makefile` that orchestrates the whole lifecycle, and `srcs/` containing the
`docker-compose.yml` plus one build context per service
(`srcs/requirements/<service>/` = `Dockerfile` + `conf/` + `tools/entrypoint.sh`).
Docker builds each service into an isolated, reproducible image; Compose wires the
three containers together over a private bridge network, mounts the named volumes, and
injects configuration (environment variables) and credentials (secrets). The stack can
be destroyed and rebuilt identically in seconds with `make re` — see `DEV_DOC.md` for
the main design choices and the performance work behind them.

### Virtual Machines vs Docker

| Aspect | Virtual Machine | Docker Container |
|--------|----------------|-----------------|
| **Isolation** | Full hardware-level (hypervisor) | Process-level (kernel namespaces + cgroups) |
| **Boot time** | Minutes | Seconds |
| **Resource overhead** | High (full guest OS) | Minimal (shares host kernel) |
| **Image size** | Gigabytes | Megabytes (Alpine ≈ 5 MB) |
| **Portability** | Limited to hypervisor | Runs anywhere Docker is installed |
| **Use case** | Different OS kernels, strong security boundaries | Microservices, CI/CD, reproducible builds |

### Secrets vs Environment Variables

| Aspect | Environment Variables | Docker Secrets |
|--------|----------------------|---------------|
| **Visibility** | Visible in `docker inspect`, process table | Mounted as files at `/run/secrets/` |
| **Persistence** | Stored in compose file or `.env` | Stored in separate files, referenced by compose |
| **Security** | Acceptable for non-sensitive config | Required for passwords, keys, credentials |
| **Git safety** | `.env` in `.gitignore` | `secrets/` directory in `.gitignore` |

In this project, non-sensitive configuration (domain name, database name, usernames) is
passed via environment variables, while all passwords are delivered exclusively as
Docker secrets with root-only file modes. The TLS server key is also a secret, and the
CA private key never leaves the host.

### Docker Network vs Host Network

| Aspect | Docker Bridge Network | Host Network |
|--------|----------------------|-------------|
| **Isolation** | Containers have private IPs on a virtual bridge | Containers share the host's network stack |
| **Security** | Nothing exposed unless explicitly published | All container ports directly on the host |
| **Service discovery** | Containers resolve each other by service name | `localhost` + unique ports |
| **Port conflicts** | None (each container has its own IP) | Possible |

This project uses a **bridge network** (`inception`) — only NGINX's port 443 is
published; WordPress and MariaDB are unreachable from outside the Docker network.
`network_mode: host` and `links:` are forbidden by the subject and absent.

### Docker Volumes vs Bind Mounts

| Aspect | Named Volumes | Bind Mounts |
|--------|--------------|-------------|
| **Management** | Managed by Docker (`docker volume ls`) | Direct host path in the service definition |
| **Portability** | Higher — the name abstracts the location | Lower — tied to host filesystem layout |
| **Permissions** | Docker handles ownership | Host file permissions apply |
| **Lifecycle** | Independent of containers | None (just a path) |

This project uses **named volumes** (`inception_db_data`, `inception_wp_data`) declared
at the top level of the compose file with `driver: local` and a `device` option, so
their data lives at the deterministic host path `/home/dlesieur/data/` required by the
subject while remaining proper Docker named volumes — no service ever bind-mounts a
host path directly.

https://claude.ai/code/artifact/eb6cda86-9cb1-4c06-9687-c7d755273291?via=auto_preview