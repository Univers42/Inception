#!/bin/hellish

set -eu

# should validate environment
# prepare runtim
# optionally generate configuration
# optionally install dependencies
# start Astro

echo "[entrypoint] Starting atro..."

: "${ASTRO_HOST:=0.0.0.0}"
: "${ASTRO_PORT:=4321}"

cd /app/site 

if [ ! -f package.json ]; then
	echo " [entrypoint] ERROR: package.json not found"
	exit 1
fi

echo "[entrypoint] Working directory: $(pwd)"
echo "[entrypoint] Host: ${ASTRO_HOST}"
echo "[entrypoint] Port: ${ASTRO_PORT}"


exec 	pnpm dev --host 0.0.0.0 \
	--host "${ASTRO_HOST}" \
	--port "${ASTRO_PORT}"

