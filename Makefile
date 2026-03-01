# ── Inception ─────────────────────────────────────────────────────────
export DOCKER_BUILDKIT   = 1
export COMPOSE_DOCKER_CLI_BUILD = 1

COMPOSE  = docker compose -f srcs/docker-compose.yml
DATA_DIR = /home/dlesieur/data
LOGIN    = dlesieur

# ── Default target ───────────────────────────────────────────────────
all: up

# ── Build & start ────────────────────────────────────────────────────
up: setup
	$(COMPOSE) up -d --build

# ── Build images only (no start) ─────────────────────────────────────
build: setup
	$(COMPOSE) build --parallel

# ── Setup host directories, /etc/hosts & local CA ────────────────────
CA_DIR  = secrets
CA_KEY  = $(CA_DIR)/ca.key
CA_CRT  = $(CA_DIR)/ca.crt

setup:
	@mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress $(CA_DIR)
	@if ! grep -q "$(LOGIN).42.fr" /etc/hosts 2>/dev/null; then \
		echo "127.0.0.1 $(LOGIN).42.fr" | sudo tee -a /etc/hosts > /dev/null; \
	fi
	@if [ ! -f $(CA_CRT) ]; then \
		echo "[setup] Generating local Root CA …"; \
		openssl ecparam -genkey -name prime256v1 -out $(CA_KEY) 2>/dev/null; \
		openssl req -new -x509 -nodes -days 3650 \
			-key  $(CA_KEY) \
			-out  $(CA_CRT) \
			-subj "/C=FR/ST=IDF/L=Paris/O=42/OU=Inception/CN=Inception Local CA"; \
		echo "[setup] CA certificate created at $(CA_CRT)"; \
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

# ── WordPress health check ───────────────────────────────────────────
WP      = docker exec wordpress wp --allow-root --path=/var/www/html
SITE    = https://$(LOGIN).42.fr
ADMIN   = $(SITE)/wp-admin

run_wp: up
	@echo "\n\033[1;33m⏳ Waiting for containers to be ready…\033[0m"
	@until docker exec mariadb mysqladmin ping -h localhost --silent 2>/dev/null; do \
		printf "."; sleep 2; \
	done && echo " MariaDB ✔"
	@until docker exec wordpress php-fpm83 -t 2>/dev/null; do \
		printf "."; sleep 2; \
	done 2>/dev/null && echo " php-fpm ✔"
	@until curl -ks --max-time 2 "$(SITE)" >/dev/null 2>&1; do \
		printf "."; sleep 2; \
	done && echo " NGINX ✔"
	@echo ""
	@echo "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
	@echo "\033[1;34m  WordPress core\033[0m"
	@echo "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
	@$(WP) core version
	@$(WP) core verify-checksums && echo "Checksums: \033[0;32mOK\033[0m" || echo "Checksums: \033[0;31m⚠ mismatch\033[0m"
	@echo "\n\033[1;34m━━ Site \033[0m"
	@$(WP) option get siteurl
	@$(WP) option get blogname
	@echo "\n\033[1;34m━━ Database \033[0m"
	@$(WP) db check && echo "\033[0;32mDB OK\033[0m" || echo "\033[0;31m⚠ DB error\033[0m"
	@echo "\n\033[1;34m━━ Users \033[0m"
	@$(WP) user list --fields=ID,user_login,roles,user_email
	@echo "\n\033[1;34m━━ Plugins \033[0m"
	@$(WP) plugin list --fields=name,status,version
	@echo "\n\033[1;34m━━ Themes \033[0m"
	@$(WP) theme list --fields=name,status,version
	@echo "\n\033[1;34m━━ PHP / OPcache \033[0m"
	@$(WP) eval 'echo "PHP " . PHP_VERSION . "\n"; echo "OPcache: " . (function_exists("opcache_get_status") && opcache_get_status() ? "enabled" : "disabled") . "\n";'
	@echo ""
	@echo "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
	@echo "\033[1;32m✔ All services are up and healthy!\033[0m"
	@echo "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
	@printf "  \033[1mSite:        \033[0m\033]8;;$(SITE)\033\\$(SITE)\033]8;;\033\\\n"
	@printf "  \033[1mAdmin panel: \033[0m\033]8;;$(ADMIN)\033\\$(ADMIN)\033]8;;\033\\\n"
	@echo "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n"
	@xdg-open "$(SITE)" 2>/dev/null || true

# ── Trust the local CA on the host system ────────────────────────────
trust:
	@if [ ! -f $(CA_CRT) ]; then echo "Run 'make setup' first."; exit 1; fi
	@echo "[trust] Installing CA into system trust store …"
	@sudo cp $(CA_CRT) /usr/local/share/ca-certificates/inception-ca.crt
	@sudo update-ca-certificates
	@echo "[trust] Installing CA into Chrome/Chromium NSS database …"
	@for db in $$(find ~/.pki/nssdb -name "cert9.db" 2>/dev/null); do \
		dir=$$(dirname "$$db"); \
		certutil -d sql:"$$dir" -D -n "Inception Local CA" 2>/dev/null || true; \
		certutil -d sql:"$$dir" -A -t "CT,C,C" -n "Inception Local CA" -i $(CA_CRT); \
	done
	@echo "[trust] Installing CA into Firefox NSS databases …"
	@for db in $$(find ~/.mozilla/firefox -name "cert9.db" 2>/dev/null); do \
		dir=$$(dirname "$$db"); \
		certutil -d sql:"$$dir" -D -n "Inception Local CA" 2>/dev/null || true; \
		certutil -d sql:"$$dir" -A -t "CT,C,C" -n "Inception Local CA" -i $(CA_CRT); \
	done
	@echo "\033[1;32m✔ CA trusted everywhere (system, Chrome, Firefox, curl).\033[0m"
	@echo "\033[1;33m⚠  Restart your browser for changes to take effect.\033[0m"

# ── Cleanup ──────────────────────────────────────────────────────────
clean: down
	$(COMPOSE) down -v --rmi all --remove-orphans
	@sudo rm -rf $(DATA_DIR)

fclean: clean
	docker system prune -af --volumes
	@sudo rm -f /usr/local/share/ca-certificates/inception-ca.crt 2>/dev/null; \
		sudo update-ca-certificates 2>/dev/null || true

re: fclean all

.PHONY: all up build setup down stop start restart logs status run_wp trust clean fclean re
