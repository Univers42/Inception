# The shell inside the containers

Every image copies this directory (a second build context, `shell`, in
`docker-compose.yml`) and, when it holds an executable named `sh`, links
`/bin/sh` to it as the last build step. `make setup` puts a copy of the static
shell the host was built with here -- `INCEPTION_SHELL=/path/to/static/binary`,
or the shell `make` was launched from when it is static, or
`/usr/bin/hellish.real` (what born2root installs in its guest) -- and removes it
when none of those exists, so the images then keep busybox's sh.

Only this README is tracked. The binary is gitignored: it is the host's, not
the project's.
