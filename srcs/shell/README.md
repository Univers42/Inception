# The shell inside the containers

This project runs on **hellish** and nothing else. Every script under `srcs/` and
`tests/` carries a `#!/bin/hellish` shebang, so a container whose image has no
hellish cannot start its entrypoint at all.

Every image copies this directory (a second build context, `shell`, in
`docker-compose.yml`) and links **both** `/bin/hellish` and `/bin/sh` to the
binary named `hellish` here, as the last build step. `/bin/sh` is pointed at it
too so that `docker exec <c> sh`, Docker's shell-form `HEALTHCHECK`, and anything
else that reaches for `sh` also get hellish rather than busybox.

`make setup` stages that binary: it resolves `INCEPTION_SHELL` (default: the
hellish the Makefile itself is running under), refuses it if it is not
statically linked — the images are Alpine/musl and nothing from the host's libc
can follow — and copies it here. If hellish cannot be found or is dynamic, the
build stops with an explanation instead of silently falling back.

Only this README is tracked. The binary is gitignored: it is the host's, not the
project's. Verify the whole chain with `make hellish-check`.
