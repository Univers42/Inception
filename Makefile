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

# ── Setup host directories & /etc/hosts ──────────────────────────────
setup:
	@mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress
	@if ! grep -q "$(LOGIN).42.fr" /etc/hosts 2>/dev/null; then \
		echo "127.0.0.1 $(LOGIN).42.fr" | sudo tee -a /etc/hosts > /dev/null; \
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
WP = docker exec wordpress wp --allow-root --path=/var/www/html

run_wp:
	@echo "\n\033[1;34m━━ WordPress core ━━\033[0m"
	@$(WP) core version
	@$(WP) core verify-checksums && echo "Checksums OK" || echo "⚠ Checksum mismatch"
	@echo "\n\033[1;34m━━ Site info ━━\033[0m"
	@$(WP) option get siteurl
	@$(WP) option get blogname
	@echo "\n\033[1;34m━━ Database connection ━━\033[0m"
	@$(WP) db check && echo "DB OK" || echo "⚠ DB error"
	@echo "\n\033[1;34m━━ Users ━━\033[0m"
	@$(WP) user list --fields=ID,user_login,roles,user_email
	@echo "\n\033[1;34m━━ Plugins ━━\033[0m"
	@$(WP) plugin list --fields=name,status,version
	@echo "\n\033[1;34m━━ Themes ━━\033[0m"
	@$(WP) theme list --fields=name,status,version
	@echo "\n\033[1;34m━━ php-fpm & OPcache ━━\033[0m"
	@$(WP) eval 'echo "PHP " . PHP_VERSION . "\n"; echo "OPcache: " . (function_exists("opcache_get_status") ? "enabled" : "disabled") . "\n";'
	@echo "\n\033[1;32m✔ All checks done\033[0m\n"

# ── Cleanup ──────────────────────────────────────────────────────────
clean: down
	$(COMPOSE) down -v --rmi all --remove-orphans
	@sudo rm -rf $(DATA_DIR)

fclean: clean
	docker system prune -af --volumes

re: fclean all

.PHONY: all up build setup down stop start restart logs status run_wp clean fclean re
