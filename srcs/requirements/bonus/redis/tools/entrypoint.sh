#!/bin/sh
set -eu

echo "[entrypoint] Starting Redis (object cache for WordPress) ..."

# exec: redis-server becomes PID 1, so Docker's stop signal and restart policy
# act on the daemon itself rather than on a shell wrapping it.
exec redis-server /etc/redis.conf
