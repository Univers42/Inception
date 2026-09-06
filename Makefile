# ── Inception ─────────────────────────────────────────────────────────
export DOCKER_BUILDKIT          = 1
export COMPOSE_DOCKER_CLI_BUILD = 1
export COMPOSE_BAKE             = true
# skip SBOM/provenance attestation generation — pure build-time overhead here
export BUILDX_NO_DEFAULT_ATTESTATIONS = 1

COMPOSE  = docker compose -f srcs/docker-compose.yml

# ── Which shell interprets the recipes and the test scripts ──────────────────
# make parses this file; the recipes and tests/*.sh are interpreted by a
# shell. Use the shell you launched make FROM -- hellish when that is your
# login shell in the VM -- and fall back to /bin/sh. The launcher is make's
# parent process; a candidate is used only if it runs a POSIX snippet, so a
# shell that cannot interpret these recipes is never picked. Override with
# `make ... SHELL=/path/to/shell`. Exported, so the recursive `make certs`
# and the scripts themselves inherit the same choice without re-probing.
ifeq ($(origin SCRIPT_SH),undefined)
SCRIPT_SH := $(shell \
	up=$$(ps -o ppid= -p $$PPID 2>/dev/null | tr -d " "); \
	launcher=$$(ps -o comm= -p "$$up" 2>/dev/null | sed "s/^-//"); \
	for c in "$$launcher" "$$SHELL" /bin/sh; do \
		[ -n "$$c" ] || continue; \
		p=$$(command -v "$$c" 2>/dev/null) || continue; \
		"$$p" -c 'a=1; f() { [ "$$a" = 1 ]; }; f && printf "%s" ok' 2>/dev/null \
			| grep -q ok && { printf "%s" "$$p"; break; }; \
	done)
SCRIPT_SH := $(if $(strip $(SCRIPT_SH)),$(strip $(SCRIPT_SH)),/bin/sh)
endif
export SCRIPT_SH
SHELL := $(SCRIPT_SH)

# ── Which shell interprets the scripts INSIDE the containers ─────────────────
# Every image links /bin/sh to srcs/shell/sh when that file exists (see
# srcs/shell/README.md), so the entrypoints, the healthchecks and every
# `docker exec ... sh` run under the same shell the host does. It has to be a
# static binary -- the images are Alpine, nothing from the host's libc can
# follow -- so: an explicit INCEPTION_SHELL, else the launching shell itself
# when it is static, else /usr/bin/hellish.real (what born2root installs in
# its guest), else nothing and the images keep busybox's sh.
ifeq ($(origin INCEPTION_SHELL),undefined)
INCEPTION_SHELL := $(shell for c in "$(SCRIPT_SH)" /usr/bin/hellish.real; do \
	[ -x "$$c" ] || continue; \
	ldd "$$c" 2>&1 | grep -qiE 'not a (valid )?dynamic|statically' && { printf "%s" "$$c"; break; }; \
	done)
endif
export INCEPTION_SHELL
DATA_DIR = /home/dlesieur/data
LOGIN    = dlesieur

SECRETS  = secrets
CA_KEY   = $(SECRETS)/ca.key
CA_CRT   = $(SECRETS)/ca.crt
SRV_KEY  = $(SECRETS)/server.key
SRV_CRT  = $(SECRETS)/server.crt

# ── Default target ───────────────────────────────────────────────────
all: up

# ── Build & start ────────────────────────────────────────────────────
up: setup
	$(COMPOSE) up -d --build

# ── Build images only (no start) ─────────────────────────────────────
build: setup
	$(COMPOSE) build

# ── Setup: data dirs, .env, secrets, /etc/hosts, TLS material ────────
# Everything is generated only if missing, so a fresh clone starts with
# a single `make` while existing credentials are never overwritten.
setup:
	@mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress $(DATA_DIR)/backups $(SECRETS)
	@if [ ! -f srcs/.env ]; then \
		sed 's/login\.42\.fr/$(LOGIN).42.fr/g' .env.example > srcs/.env; \
		echo "[setup] Generated srcs/.env — edit it to customise"; \
	fi
	@for f in db_password db_root_password ftp_password; do \
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
		echo "127.0.0.1 $(LOGIN).42.fr" | sudo tee -a /etc/hosts > /dev/null; \
	fi
	@mkdir -p srcs/shell; \
	if [ -n "$(INCEPTION_SHELL)" ]; then \
		if ! cmp -s "$(INCEPTION_SHELL)" srcs/shell/sh 2>/dev/null; then \
			cp -f "$(INCEPTION_SHELL)" srcs/shell/sh && chmod 755 srcs/shell/sh; \
			echo "[setup] /bin/sh in the images will be $(INCEPTION_SHELL)"; \
		fi; \
	elif [ -e srcs/shell/sh ]; then \
		rm -f srcs/shell/sh; echo "[setup] no static shell at hand — the images keep busybox sh"; \
	fi
	@$(MAKE) --no-print-directory certs

# ── TLS: local root CA + server certificate signed on the HOST ───────
# The CA private key never enters any container; nginx only receives
# the server certificate and its key as Docker secrets.
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

# ── Stop / start / restart ──────────────────────────────────────────
down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

restart:
	$(COMPOSE) restart

# ── Logs & status ────────────────────────────────────────────────────
logs:
	$(COMPOSE) logs -f

status:
	$(COMPOSE) ps

# ── Compliance tests & benchmarks ────────────────────────────────────
test:
	@$(SCRIPT_SH) tests/compliance.sh

test-deep:
	@$(SCRIPT_SH) tests/compliance.sh --deep

bench:
	@$(SCRIPT_SH) tests/bench.sh

bench-full:
	@$(SCRIPT_SH) tests/bench.sh --with-boot

# ── WordPress health check ───────────────────────────────────────────
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

# ── Trust the local CA on the host system ────────────────────────────
# Browsers do NOT read the system store: Chrome/Chromium use NSS user
# databases and Firefox uses per-profile databases — and on modern
# Ubuntu both are snaps whose profiles live under ~/snap/. This target
# covers deb, snap and flatpak locations, installs the Firefox
# enterprise policy (the reliable channel for snap Firefox), verifies
# every insertion, and fails loudly instead of pretending success.
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

# ── Cleanup ──────────────────────────────────────────────────────────
clean: down
	$(COMPOSE) down -v --rmi all --remove-orphans
	@sudo rm -rf $(DATA_DIR)

fclean: clean
	docker system prune -af --volumes
	@sudo rm -f /usr/local/share/ca-certificates/inception-ca.crt 2>/dev/null; \
		sudo update-ca-certificates 2>/dev/null || true

# Full rebuild of this project only: clean removes its containers,
# volumes, images and host data, then everything is rebuilt. Docker's
# build cache and other projects are left untouched (use fclean for a
# machine-wide wipe).
re: clean all

.PHONY: all up build setup certs down stop start restart logs status \
	test test-deep bench bench-full run_wp trust clean fclean re
