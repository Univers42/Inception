export DOCKER_BUILDKIT          = 1
export COMPOSE_DOCKER_CLI_BUILD = 1
export COMPOSE_BAKE             = true
export BUILDX_NO_DEFAULT_ATTESTATIONS = 1

# srcs/docker-compose.local.yml (git-ignored, see the .example) carries host-only
# port remaps for a rootless Docker daemon that cannot bind 443. When it is
# absent — the VM, the evaluation machine — nothing changes.
COMPOSE_LOCAL = $(wildcard srcs/docker-compose.local.yml)
COMPOSE  = docker compose -f srcs/docker-compose.yml $(if $(COMPOSE_LOCAL),-f $(COMPOSE_LOCAL))

ifeq ($(origin SCRIPT_SH),undefined)
# The five system paths are where a packaged hellish lands. A hellish built or
# downloaded by hand lands in the user's own bin — on a 42 machine there is no
# root, so that is the ONLY place it can be. `command -v` is asked last, so a
# system install still wins; the probe still decides: a candidate is used only
# if it prints INC_SH=<path> for itself.
_inc_cands := $(wildcard /bin/hellish /usr/bin/hellish /usr/local/bin/hellish \
	/bin/hellish.real /usr/bin/hellish.real) \
	$(shell command -v hellish 2>/dev/null) \
	$(shell command -v hellish.real 2>/dev/null)
_inc_try    = $(filter INC_SH=%,$(shell $(1) tests/launcher_probe.sh 2>/dev/null))
_inc_found := $(firstword $(foreach c,$(_inc_cands),$(call _inc_try,$(c))))
SCRIPT_SH  := $(strip $(patsubst INC_SH=%,%,$(_inc_found)))
endif
export SCRIPT_SH

ifeq ($(strip $(SCRIPT_SH)),)
$(info )
$(info   hellish was not found, or it is present but did not interpret)
$(info   tests/launcher_probe.sh as a POSIX shell.)
$(info )
$(info   This project runs on hellish and nothing else: every script under)
$(info   srcs/ and tests/ carries a '#!/bin/hellish' shebang, and every image)
$(info   links /bin/sh to the hellish binary copied in by 'make setup'.)
$(info )
$(info   Install hellish, or point the build at it explicitly:)
$(info     make SCRIPT_SH=/path/to/hellish)
$(info )
$(error no usable hellish interpreter)
endif

SHELL := $(SCRIPT_SH)

INCEPTION_SHELL ?= $(SCRIPT_SH)
export INCEPTION_SHELL
# Host-only settings (git-ignored, see srcs/local.mk.example): where the volumes
# live and where the Docker CLI keeps its state on a machine whose home is too
# small. Absent on the VM and the evaluation machine, where nothing changes.
-include srcs/local.mk
DATA_DIR ?= /home/dlesieur/data
export INCEPTION_DATA_DIR := $(DATA_DIR)
ifneq ($(strip $(DOCKER_CONFIG)),)
export DOCKER_CONFIG
$(shell mkdir -p $(DOCKER_CONFIG))
endif
LOGIN    = dlesieur

# The images inside the containers are Alpine (musl), so the hellish linked in
# as /bin/sh must be static. The release channel publishes one; `hellish-fetch`
# stages it with its checksum verified.
HELLISH_VERSION ?= v2.10.1
HELLISH_URL      = https://github.com/Univers42/hellish/releases/download/$(HELLISH_VERSION)

# Throwaway image used only to wipe $(DATA_DIR) without sudo (same pin as every
# Dockerfile: it is the base OS, the one image the subject allows to be pulled).
BASE_IMAGE = alpine:3.23

SECRETS  = secrets
CA_KEY   = $(SECRETS)/ca.key
CA_CRT   = $(SECRETS)/ca.crt
SRV_KEY  = $(SECRETS)/server.key
SRV_CRT  = $(SECRETS)/server.crt

# HTTPS port as seen from this host: 443 by default, the remapped port when the
# local override is in use. Used by targets that talk to the running stack.
HTTPS_PORT ?= $(if $(COMPOSE_LOCAL),$(shell sed -n 's/^[[:space:]]*- *"\([0-9]*\):443".*/\1/p' $(COMPOSE_LOCAL) | head -1),443)
SITE_CURL   = curl -ks --resolve $(LOGIN).42.fr:$(HTTPS_PORT):127.0.0.1
SITE_URL    = https://$(LOGIN).42.fr$(if $(filter-out 443,$(HTTPS_PORT)),:$(HTTPS_PORT))

all: up

up: setup
	$(COMPOSE) up -d --build

build: setup
	$(COMPOSE) build

# Rebuild every image from scratch, ignoring the layer cache.
rebuild: setup
	$(COMPOSE) build --no-cache

setup:
	@mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress $(DATA_DIR)/backups $(SECRETS)
	@if [ ! -f srcs/.env ]; then \
		sed 's/login\.42\.fr/$(LOGIN).42.fr/g' .env.example > srcs/.env; \
		echo "[setup] Generated srcs/.env — edit it to customise"; \
	fi
	@for f in db_password db_root_password ftp_password api_db_password; do \
		if [ ! -f $(SECRETS)/$$f.txt ]; then \
			openssl rand -base64 24 | tr -d '/+=' > $(SECRETS)/$$f.txt; \
			chmod 600 $(SECRETS)/$$f.txt; \
			echo "[setup] Generated random $(SECRETS)/$$f.txt"; \
		fi; \
	done
	@if [ ! -f $(SECRETS)/credentials.txt ]; then \
		printf '%s\n%s\n' "$$(openssl rand -base64 24 | tr -d '/+=')" \
			"$$(openssl rand -base64 24 | tr -d '/+=')" > $(SECRETS)/credentials.txt; \
		chmod 600 $(SECRETS)/credentials.txt; \
		echo "[setup] Generated random $(SECRETS)/credentials.txt (line 1 = WP admin, line 2 = editor)"; \
	fi
	@if ! grep -q "$(LOGIN).42.fr" /etc/hosts 2>/dev/null; then \
		if sudo -n true 2>/dev/null; then \
			echo "127.0.0.1 $(LOGIN).42.fr" | sudo tee -a /etc/hosts > /dev/null; \
		else \
			echo "[setup] WARN: $(LOGIN).42.fr is not in /etc/hosts and sudo is not available."; \
			echo "[setup]       Add it yourself:  echo '127.0.0.1 $(LOGIN).42.fr' | sudo tee -a /etc/hosts"; \
			echo "[setup]       Meanwhile: curl -k --resolve $(LOGIN).42.fr:$(HTTPS_PORT):127.0.0.1 $(SITE_URL)/"; \
		fi; \
	fi
	@mkdir -p srcs/shell; \
	rm -f srcs/shell/sh; \
	src=$$(readlink -f "$(INCEPTION_SHELL)"); \
	is_static() { ldd "$$1" 2>&1 | grep -qiE 'not a (valid )?dynamic|statically'; }; \
	if is_static "$$src"; then \
		if ! cmp -s "$$src" srcs/shell/hellish 2>/dev/null; then \
			cp -f "$$src" srcs/shell/hellish && chmod 755 srcs/shell/hellish; \
			echo "[setup] hellish staged for the images from $$src"; \
		fi; \
	elif [ -x srcs/shell/hellish ] && is_static srcs/shell/hellish; then \
		echo "[setup] $$src is dynamically linked; keeping the static hellish already staged in srcs/shell/"; \
	else \
		echo "[setup] ERROR: $$src is dynamically linked and no static hellish is staged." >&2; \
		echo "[setup] The images are Alpine (musl); a glibc-linked hellish cannot run in them." >&2; \
		echo "[setup] Run 'make hellish-fetch' (static release binary, checksum verified), or:" >&2; \
		echo "[setup]   make INCEPTION_SHELL=/path/to/static/hellish"                          >&2; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory certs

# Stage the static hellish release binary in srcs/shell/ (no root needed).
hellish-fetch:
	@mkdir -p srcs/shell; \
	echo "[hellish] fetching $(HELLISH_VERSION) static binary ..."; \
	curl -fsSL "$(HELLISH_URL)/hellish-linux-x86_64"        -o srcs/shell/.hellish.tmp    || exit 1; \
	curl -fsSL "$(HELLISH_URL)/hellish-linux-x86_64.sha256" -o srcs/shell/.hellish.sha256 || exit 1; \
	want=$$(cut -d' ' -f1 srcs/shell/.hellish.sha256); \
	got=$$(sha256sum srcs/shell/.hellish.tmp | cut -d' ' -f1); \
	if [ "$$want" != "$$got" ]; then \
		echo "[hellish] ERROR: checksum mismatch (want $$want, got $$got)" >&2; \
		rm -f srcs/shell/.hellish.tmp srcs/shell/.hellish.sha256; exit 1; \
	fi; \
	if ! ldd srcs/shell/.hellish.tmp 2>&1 | grep -qiE 'not a (valid )?dynamic|statically'; then \
		echo "[hellish] ERROR: the release binary is not statically linked" >&2; \
		rm -f srcs/shell/.hellish.tmp srcs/shell/.hellish.sha256; exit 1; \
	fi; \
	mv -f srcs/shell/.hellish.tmp srcs/shell/hellish && chmod 755 srcs/shell/hellish; \
	rm -f srcs/shell/.hellish.sha256; \
	echo "[hellish] staged srcs/shell/hellish (sha256 $$got)"

certs:
	@if [ ! -f $(CA_CRT) ]; then \
		echo "[setup] Generating local Root CA ..."; \
		openssl ecparam -genkey -name prime256v1 -out $(CA_KEY) 2>/dev/null; \
		openssl req -new -x509 -nodes -days 3650 -key $(CA_KEY) -out $(CA_CRT) \
			-subj "/C=FR/ST=IDF/L=Paris/O=42/OU=Inception/CN=Inception Local CA"; \
		chmod 600 $(CA_KEY); \
	fi
	@DOMAIN=$$(sed -n 's/^DOMAIN_NAME=//p' srcs/.env); \
	[ -n "$$DOMAIN" ] || DOMAIN=$(LOGIN).42.fr; \
	if [ ! -f $(SRV_CRT) ] || ! openssl x509 -in $(SRV_CRT) -noout -text | grep -q "DNS:$$DOMAIN"; then \
		echo "[setup] Issuing server certificate for $$DOMAIN ..."; \
		openssl ecparam -genkey -name prime256v1 -out $(SRV_KEY) 2>/dev/null; \
		openssl req -new -key $(SRV_KEY) -out $(SECRETS)/server.csr \
			-subj "/C=FR/ST=IDF/L=Paris/O=42/OU=42/CN=$$DOMAIN"; \
		printf 'authorityKeyIdentifier=keyid,issuer\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:%s,DNS:localhost,IP:127.0.0.1\n' "$$DOMAIN" \
			> $(SECRETS)/san.cnf; \
		openssl x509 -req -days 365 -in $(SECRETS)/server.csr \
			-CA $(CA_CRT) -CAkey $(CA_KEY) -CAcreateserial \
			-out $(SRV_CRT) -extfile $(SECRETS)/san.cnf 2>/dev/null; \
		rm -f $(SECRETS)/server.csr $(SECRETS)/san.cnf; \
		chmod 600 $(SRV_KEY); \
	fi

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f

status:
	$(COMPOSE) ps

ps: status

# ── Lab (bonus web + api) ────────────────────────────────────────────────────
# The site is static: pages that show database content are rendered at build
# time from JSON snapshots committed under web/app/src/data. `snapshot` refreshes
# them from the running API — through nginx, from the host, like any client —
# and `re-web` rebuilds only the web image so the new content ships.
SNAP_DIR = srcs/requirements/bonus/web/app/src/data

snapshot:
	@mkdir -p $(SNAP_DIR); \
	for e in flights stats; do \
		if $(SITE_CURL) -f "$(SITE_URL)/api/v1/$$e" -o $(SNAP_DIR)/$$e.json.tmp; then \
			mv -f $(SNAP_DIR)/$$e.json.tmp $(SNAP_DIR)/$$e.json; \
			echo "[snapshot] $(SNAP_DIR)/$$e.json refreshed"; \
		else \
			rm -f $(SNAP_DIR)/$$e.json.tmp; \
			echo "[snapshot] ERROR: could not fetch /api/v1/$$e from $(SITE_URL) (is the stack up?)" >&2; \
			exit 1; \
		fi; \
	done; \
	ng=$$(docker exec nginx nginx -v 2>&1 | sed 's|.*/||'); \
	php=$$(docker exec wordpress php -r 'echo PHP_VERSION;'); \
	wp=$$(docker exec wordpress wp --allow-root --path=/var/www/html core version 2>/dev/null); \
	mdb=$$(docker exec mariadb mariadbd --version | sed 's/.*Ver \([0-9.]*\).*/\1/'); \
	rds=$$(docker exec redis redis-server --version | sed 's/.*v=\([0-9.]*\).*/\1/'); \
	nd=$$(docker exec api node -p process.versions.node); \
	alp=$$(docker exec nginx cat /etc/alpine-release | cut -d. -f1,2); \
	if [ -z "$$ng" ] || [ -z "$$mdb" ] || [ -z "$$nd" ]; then \
		echo "[snapshot] ERROR: could not read daemon versions (are the containers up?)" >&2; exit 1; \
	fi; \
	printf '{"alpine":"%s","nginx":"%s","php":"%s","wordpress":"%s","mariadb":"%s","redis":"%s","node":"%s","snapshot_at":"%s"}\n' \
		"$$alp" "$$ng" "$$php" "$$wp" "$$mdb" "$$rds" "$$nd" "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" > $(SNAP_DIR)/stack.json; \
	echo "[snapshot] $(SNAP_DIR)/stack.json refreshed ($$(cat $(SNAP_DIR)/stack.json))"

re-web:
	$(COMPOSE) up -d --build web

# LAB_ARGS=--deep adds the SIGTERM drain and the late-MariaDB start.
test-lab:
	@HTTPS_PORT=$(HTTPS_PORT) $(SCRIPT_SH) tests/lab.sh $(LAB_ARGS)

# ── nodetool: the only node/npm this project ever runs ───────────────────────
# No Node toolchain on the host. Lockfiles are resolved, and any npm command is
# run, inside an image built from srcs/requirements/bonus/nodetool — the same
# alpine:3.23 + apk nodejs/npm the web and api build stages use. Like 42ctl it
# is a CLI image, not a compose service (a CLI cannot be an honest PID-1 daemon).
#   make lock                                   # (re)resolve both lockfiles
#   make npm-web NPM="install --package-lock-only"
#   make npm-api NPM="outdated"
NODE_DIR   = srcs/requirements/bonus/nodetool
NODE_IMAGE = nodetool:inception
WEB_APP    = srcs/requirements/bonus/web/app
API_APP    = srcs/requirements/bonus/api/app
LOCK_ARGS  = install --package-lock-only --ignore-scripts --no-audit --no-fund

# Rootless daemon: container root IS the developer, so run as root. Rootful:
# run as the developer's uid so the files npm writes are not root-owned.
# $(1) = app directory (bind-mounted at /app), $(2) = npm arguments.
NODE_RUN = u=0; docker info --format '{{.SecurityOptions}}' 2>/dev/null | grep -q 'name=rootless' || u="$$(id -u):$$(id -g)"; \
	docker run --rm -u "$$u" -v "$$PWD/$(1)":/app $(NODE_IMAGE) $(2)

nodetool:
	@echo "[nodetool] building $(NODE_IMAGE) ..."; \
	docker build -t $(NODE_IMAGE) $(NODE_DIR)

nodetool-present:
	@docker image inspect $(NODE_IMAGE) >/dev/null 2>&1 || $(MAKE) --no-print-directory nodetool

npm-web: nodetool-present
	@$(call NODE_RUN,$(WEB_APP),$(NPM))

npm-api: nodetool-present
	@$(call NODE_RUN,$(API_APP),$(NPM))

lock: nodetool-present
	@for d in $(WEB_APP) $(API_APP); do \
		echo "[lock] $$d/package-lock.json"; \
		$(call NODE_RUN,$$d,$(LOCK_ARGS)) || exit 1; \
	done

# ── 42ctl: the vault42 remote controller ─────────────────────────────────────
# Built from source (never pulled) into a local image, then invoked one shot at a
# time. It is deliberately NOT a compose service: a CLI exits when its command is
# done, and an Inception service must run a real daemon as PID 1 with no
# keep-alive hack (compliance S06/S18/S23, R10/R19).
C42_DIR  = srcs/requirements/bonus/42ctl
C42_CONF = $(C42_DIR)/conf/42ctl.conf
C42_ENV  = set -a; . ./$(C42_CONF); set +a

42ctl:
	@$(C42_ENV); \
	echo "[42ctl] building $$C42_IMAGE from $$C42_REPO@$$C42_REF ..."; \
	docker build \
		--build-arg C42_REPO="$$C42_REPO" \
		--build-arg C42_REF="$$C42_REF" \
		-t "$$C42_IMAGE" $(C42_DIR)

# The repo is the tree the CLI acts on; the host's ~/.42ctl carries the identity
# keypair and session, so no secret is ever baked into the image or the repo.
C42_RUN = $(C42_ENV); mkdir -p "$$HOME/.42ctl"; \
	docker run --rm -i \
		-v "$$PWD":/work -w /work \
		-v "$$HOME/.42ctl":/home/nonroot/.42ctl \
		-e FT_PROFILE="$$C42_PROFILE" \
		"$$C42_IMAGE"

42ctl-present:
	@$(C42_ENV); \
	docker image inspect "$$C42_IMAGE" >/dev/null 2>&1 \
		|| { echo "[42ctl] $$C42_IMAGE is not built — run 'make 42ctl'" >&2; exit 1; }

vault-login: 42ctl-present
	@$(C42_RUN) config endpoint --api "$$C42_ENDPOINT"
	@$(C42_RUN) auth login

vault-status: 42ctl-present
	@$(C42_RUN) config show

vault-push: 42ctl-present
	@$(C42_ENV); echo "[42ctl] pushing $$C42_PATHS -> $$C42_ENDPOINT"
	@$(C42_RUN) push

# Dry-run first: you always see what would land where before anything is written.
# `make vault-pull APPLY=1` is the second, explicit step that touches the disk.
vault-pull: 42ctl-present
ifeq ($(APPLY),1)
	@$(C42_RUN) pull --apply
else
	@$(C42_RUN) pull
	@printf '\nNothing was written. To apply: make vault-pull APPLY=1\n'
endif

hellish-check:
	@printf '\033[1;34m== hellish interpreter audit ==\033[0m\n'
	@fail=0; \
	printf '\n-- host --\n'; \
	printf '  recipes interpreted by: %s\n' "$$(readlink -f /proc/$$$$/exe)"; \
	case "$$(readlink -f /proc/$$$$/exe)" in \
		*hellish*) printf '  \033[0;32mOK\033[0m this recipe is running under hellish\n' ;; \
		*) printf '  \033[0;31mFAIL\033[0m this recipe is NOT hellish\n'; fail=1 ;; \
	esac; \
	printf '\n-- shebangs --\n'; \
	for f in $$(git ls-files | grep -E '\.sh$$'); do \
		head -1 "$$f" | grep -q '^#!/bin/hellish$$' \
			|| { printf '  \033[0;31mFAIL\033[0m %s -> %s\n' "$$f" "$$(head -1 $$f)"; fail=1; }; \
	done; \
	[ $$fail -eq 0 ] && printf '  \033[0;32mOK\033[0m all %s tracked scripts declare #!/bin/hellish\n' \
		"$$(git ls-files | grep -cE '\.sh$$')"; \
	printf '\n-- staged binary --\n'; \
	if [ -x srcs/shell/hellish ] && ldd srcs/shell/hellish 2>&1 | grep -qiE 'not a (valid )?dynamic|statically'; then \
		printf '  \033[0;32mOK\033[0m srcs/shell/hellish is staged and statically linked\n'; \
	else \
		printf '  \033[0;31mFAIL\033[0m srcs/shell/hellish missing or dynamic — run make setup (or make hellish-fetch)\n'; fail=1; \
	fi; \
	printf '\n-- containers --\n'; \
	running=0; \
	for c in nginx wordpress mariadb redis ftp adminer dbbackup staticsite web api; do \
		docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$$c" || continue; \
		running=1; \
		bin=$$(docker exec "$$c" readlink -f /bin/hellish 2>/dev/null); \
		shl=$$(docker exec "$$c" readlink -f /bin/sh 2>/dev/null); \
		if [ -z "$$bin" ]; then \
			printf '  \033[0;31mFAIL\033[0m %-11s /bin/hellish absent\n' "$$c"; fail=1; \
		elif [ "$$shl" != "$$bin" ]; then \
			printf '  \033[0;31mFAIL\033[0m %-11s /bin/sh -> %s (not hellish)\n' "$$c" "$$shl"; fail=1; \
		else \
			printf '  \033[0;32mOK\033[0m %-11s /bin/hellish + /bin/sh -> %s\n' "$$c" "$$bin"; \
		fi; \
	done; \
	[ $$running -eq 1 ] || printf '  \033[2m(stack not running — make up to audit containers)\033[0m\n'; \
	printf '\n'; \
	if [ $$fail -eq 0 ]; then printf '\033[1;32m✔ hellish is the interpreter everywhere\033[0m\n'; \
	else printf '\033[1;31m✘ hellish audit failed\033[0m\n'; exit 1; fi

test: hellish-check
	@$(SCRIPT_SH) tests/compliance.sh

test-deep:
	@$(SCRIPT_SH) tests/compliance.sh --deep

bench:
	@$(SCRIPT_SH) tests/bench.sh

bench-full:
	@$(SCRIPT_SH) tests/bench.sh --with-boot

WP      = docker exec wordpress wp --allow-root --path=/var/www/html
SITE    = https://$(LOGIN).42.fr
ADMIN   = $(SITE)/wp-admin

run_wp: up
	@printf '%b\n' "\n\033[1;33m⏳ Waiting for containers to be ready…\033[0m"
	@until docker exec mariadb mariadb-admin ping -h localhost --silent 2>/dev/null; do \
		printf "."; sleep 2; \
	done && echo " MariaDB ✔"
	@until docker exec wordpress php-fpm84 -t 2>/dev/null; do \
		printf "."; sleep 2; \
	done 2>/dev/null && echo " php-fpm ✔"
	@until curl -ks --max-time 2 "$(SITE)" >/dev/null 2>&1; do \
		printf "."; sleep 2; \
	done && echo " NGINX ✔"
	@echo ""
	@printf '%b\n' "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
	@printf '%b\n' "\033[1;34m  WordPress core\033[0m"
	@printf '%b\n' "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
	@$(WP) core version
	@$(WP) core verify-checksums && printf '%b\n' "Checksums: \033[0;32mOK\033[0m" || printf '%b\n' "Checksums: \033[0;31m⚠ mismatch\033[0m"
	@printf '%b\n' "\n\033[1;34m━━ Site \033[0m"
	@$(WP) option get siteurl
	@$(WP) option get blogname
	@printf '%b\n' "\n\033[1;34m━━ Database \033[0m"
	@$(WP) eval 'global $$wpdb; printf '%b\n' "DB connection OK — server " . $$wpdb->db_version() . "\n";'
	@printf '%b\n' "\n\033[1;34m━━ Users \033[0m"
	@$(WP) user list --fields=ID,user_login,roles,user_email
	@printf '%b\n' "\n\033[1;34m━━ Themes \033[0m"
	@$(WP) theme list --fields=name,status,version
	@printf '%b\n' "\n\033[1;34m━━ PHP / OPcache \033[0m"
	@$(WP) eval 'printf '%b\n' "PHP " . PHP_VERSION . "\n"; printf '%b\n' "OPcache: " . (function_exists("opcache_get_status") && opcache_get_status() ? "enabled" : "disabled") . "\n";'
	@echo ""
	@printf '%b\n' "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
	@printf '%b\n' "\033[1;32m✔ All services are up and healthy!\033[0m"
	@printf '%b\n' "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
	@printf "  \033[1mSite:        \033[0m\033]8;;$(SITE)\033\\$(SITE)\033]8;;\033\\\n"
	@printf "  \033[1mAdmin panel: \033[0m\033]8;;$(ADMIN)\033\\$(ADMIN)\033]8;;\033\\\n"
	@printf '%b\n' "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n"
	@xdg-open "$(SITE)" 2>/dev/null || true

trust:
	@if [ ! -f $(CA_CRT) ]; then echo "Run 'make setup' first."; exit 1; fi
	@command -v certutil >/dev/null 2>&1 || { \
		echo "[trust] Installing certutil (libnss3-tools) ..."; \
		sudo apt-get install -y libnss3-tools 2>/dev/null \
			|| sudo dnf install -y nss-tools 2>/dev/null \
			|| sudo apk add nss-tools 2>/dev/null \
			|| { echo "[trust] ERROR: install certutil manually"; exit 1; }; }
	@echo "[trust] System trust store ..."
	@sudo cp $(CA_CRT) /usr/local/share/ca-certificates/inception-ca.crt
	@sudo update-ca-certificates >/dev/null 2>&1 || true
	@echo "[trust] Firefox enterprise policy (deb + snap) ..."
	@sudo mkdir -p /etc/firefox/policies
	@sudo cp $(CA_CRT) /etc/firefox/policies/inception-ca.crt
	@printf '{\n  "policies": {\n    "Certificates": {\n      "ImportEnterpriseRoots": true,\n      "Install": ["/etc/firefox/policies/inception-ca.crt"]\n    }\n  }\n}\n' \
		| sudo tee /etc/firefox/policies/policies.json >/dev/null
	@if [ -d /usr/lib/firefox ]; then \
		sudo mkdir -p /usr/lib/firefox/distribution; \
		sudo cp /etc/firefox/policies/policies.json /usr/lib/firefox/distribution/policies.json; \
	fi
	@echo "[trust] Browser NSS databases (deb, snap, flatpak) ..."
	@if [ ! -f "$$HOME/.pki/nssdb/cert9.db" ]; then \
		mkdir -p "$$HOME/.pki/nssdb"; \
		certutil -d sql:"$$HOME/.pki/nssdb" -N --empty-password 2>/dev/null || true; \
	fi
	@FOUND=0; \
	for db in $$(find "$$HOME/.mozilla/firefox" \
			"$$HOME/snap/firefox/common/.mozilla/firefox" \
			"$$HOME/.pki/nssdb" \
			"$$HOME/snap/chromium/current/.pki/nssdb" \
			"$$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" \
			"$$HOME/.var/app/com.google.Chrome/.pki/nssdb" \
			"$$HOME/.var/app/org.chromium.Chromium/.pki/nssdb" \
			-name cert9.db 2>/dev/null); do \
		dir=$$(dirname "$$db"); \
		certutil -d sql:"$$dir" -D -n "Inception Local CA" 2>/dev/null || true; \
		if certutil -d sql:"$$dir" -A -t "CT,C,C" -n "Inception Local CA" -i $(CA_CRT) 2>/dev/null \
			&& certutil -d sql:"$$dir" -L 2>/dev/null | grep -q "Inception Local CA"; then \
			echo "  ✔ $$dir"; FOUND=$$((FOUND+1)); \
		else \
			echo "  ✘ $$dir"; \
		fi; \
	done; \
	if [ "$$FOUND" -eq 0 ]; then \
		echo "[trust] ERROR: no browser NSS database was updated"; exit 1; \
	fi
	@if pgrep -x firefox >/dev/null 2>&1 || pgrep -f "chromium|chrome" >/dev/null 2>&1; then \
		printf '%b\n' "\033[1;33m⚠  Browsers are RUNNING — quit them completely (all windows) and reopen.\033[0m"; \
	fi
	@printf '%b\n' "\033[1;32m✔ CA trusted: system store, browser NSS databases, Firefox policy.\033[0m"

# Wipe the host data directory. With sudo when it is available; otherwise from
# a throwaway container, because files written by a container's own users
# (mysql, nobody) belong to sub-uids the plain user cannot delete.
clean: down
	$(COMPOSE) down -v --rmi all --remove-orphans
	@if [ -d $(DATA_DIR) ]; then \
		if sudo -n true 2>/dev/null; then \
			sudo rm -rf $(DATA_DIR); \
		else \
			echo "[clean] no sudo: wiping $(DATA_DIR) from a throwaway $(BASE_IMAGE) container"; \
			docker run --rm -v $(DATA_DIR):/data $(BASE_IMAGE) sh -c 'rm -rf /data/* /data/.[!.]* 2>/dev/null; true'; \
			rm -rf $(DATA_DIR); \
		fi; \
	fi

# Reclaim build cache and dangling images without touching other projects' volumes.
prune:
	docker builder prune -f
	docker image prune -f

fclean: clean
	docker system prune -af --volumes
	@if sudo -n true 2>/dev/null; then \
		sudo rm -f /usr/local/share/ca-certificates/inception-ca.crt 2>/dev/null; \
		sudo update-ca-certificates 2>/dev/null || true; \
	fi

re: clean all

.PHONY: all up build rebuild setup hellish-fetch certs down stop start restart logs status ps \
	snapshot re-web test-lab nodetool nodetool-present npm-web npm-api lock \
	42ctl 42ctl-present vault-login vault-status vault-push vault-pull hellish-check \
	test test-deep bench bench-full run_wp trust clean prune fclean re
