#!/bin/hellish
# shellcheck shell=sh
set -eu

echo "[entrypoint] Starting Redis (object cache for WordPress) ..."

exec redis-server /etc/redis.conf
