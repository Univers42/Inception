# Why `tail -f`, `sleep infinity` and `while true` are wrong

The subject forbids keeping a container alive with "hacky patches" such as
`tail -f`, `bash`, `sleep infinity` or `while true`. This document explains *why*
that rule exists, with references to the official Docker documentation, and shows
what this project does instead.

---

## 1. A container's lifetime is its PID 1's lifetime

A container is not a virtual machine. It does not "boot" and then "run services":
it starts exactly one process, and it exits when that process exits. The Docker
documentation states the rule directly:

> "The `ENTRYPOINT` of an image is similar to a `COMMAND` because it specifies what
> executable to run when the container starts, but it is (purposely) more difficult
> to override. […] The container's main running process is the `ENTRYPOINT` and/or
> `CMD` at the end of the Dockerfile."
>
> — [Dockerfile reference — ENTRYPOINT](https://docs.docker.com/reference/dockerfile/#entrypoint)

So "keeping the container alive" is not a goal in itself. A container that is *up*
is only meaningful if the process holding it up **is the service**. The moment you
write

```dockerfile
CMD ["tail", "-f", "/dev/null"]
```

you have inverted the relationship: the container now stays up whether or not
nginx, php-fpm or mariadbd is running — or was ever started at all.

---

## 2. The keep-alive process makes the container lie

Everything Docker and Compose build on top of a container assumes PID 1 represents
the service:

- `docker ps` shows the container as **Up**.
- A `restart:` policy only fires when the main process dies —
  [Start containers automatically](https://docs.docker.com/engine/containers/start-containers-automatically/).
- `depends_on` gates dependent services on the container's state —
  [Control startup order](https://docs.docker.com/compose/how-tos/startup-order/).

With `tail -f` at PID 1, the daemon can crash and **none of these notice**. The
container stays Up, the restart policy never triggers, and dependents happily start
against a service that is not there. The orchestration layer is now reporting
fiction. This is strictly worse than crashing: a crash is visible, a lie is not.

---

## 3. Signals never reach the service

`docker stop` does not kill a container outright. It asks the main process to stop:

> "The `docker stop` command […] sends `SIGTERM` to the container's main process,
> then, after a grace period, `SIGKILL`."
>
> — [`docker container stop`](https://docs.docker.com/reference/cli/docker/container/stop/)

If PID 1 is `tail -f` or `sleep infinity`, that `SIGTERM` goes to the keep-alive
process, not to the database. The service is never asked to shut down; it is simply
`SIGKILL`ed with the rest of the container once the grace period expires. For
MariaDB that means no clean flush of buffers — an unclean shutdown, and crash
recovery on next boot.

The same trap applies to the Dockerfile *shell form*. `ENTRYPOINT nginx` (no JSON
array) runs as `/bin/sh -c nginx`, so the shell is PID 1 and the daemon is its
child:

> "The exec form […] is the preferred form for `ENTRYPOINT`. […] If you use the
> shell form, the executable runs as a child process of `/bin/sh -c`, which does
> not pass signals."
>
> — [Dockerfile reference — ENTRYPOINT / exec form](https://docs.docker.com/reference/dockerfile/#entrypoint)

Which is exactly why every entrypoint in this project ends with `exec`: `exec`
replaces the shell image with the daemon, so the daemon *becomes* PID 1 rather than
sitting behind one.

---

## 4. PID 1 has a job: reaping zombies

PID 1 on Linux inherits orphaned processes and is responsible for reaping them.
`tail`, `sleep` and a plain `bash` loop do not do this, so orphaned children
accumulate as zombie entries in the process table. Docker acknowledges the problem
by shipping an opt-in init:

> "`--init` — Run an init inside the container that forwards signals and reaps
> processes."
>
> — [`docker container run`](https://docs.docker.com/reference/cli/docker/container/run/#init)

Real daemons already handle their own children correctly, so running the daemon as
PID 1 avoids the problem entirely — no `--init` needed. Background on the failure
mode: [Docker and the PID 1 zombie reaping
problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/).

---

## 5. The usual excuse — "I need two things running"

The keep-alive hack is normally reached for when someone wants several services in
one container. Docker's own guidance is not to:

> "It's generally recommended that you separate areas of concern by using one
> service per container."
>
> — [Run multiple processes in a container](https://docs.docker.com/engine/containers/multi-service_container/)

That is the same separation the subject mandates: nginx, WordPress + php-fpm and
MariaDB each get their own container, their own image and their own PID 1.

---

## 6. The other excuse — "I need to wait for the database"

The second reason people fake a foreground process is ordering: WordPress must not
start before MariaDB is ready. The wrong answers are `sleep 10` (a guess that is
simultaneously too long and not long enough) and an unbounded `while true` retry
loop that never fails.

Docker's answer is a healthcheck plus a dependency condition:

> "Compose does not wait until a container is 'ready', only until it's running. […]
> The solution is to check for readiness with a healthcheck and use
> `depends_on` with `condition: service_healthy`."
>
> — [Control startup order](https://docs.docker.com/compose/how-tos/startup-order/),
> [HEALTHCHECK](https://docs.docker.com/reference/dockerfile/#healthcheck)

This project does exactly that. MariaDB reports healthy only when the *application
user* can actually connect over TCP; WordPress only when php-fpm accepts a FastCGI
connection; nginx only when HTTPS answers. The wait that does remain in the
WordPress entrypoint is **bounded** — it gives up after 60 seconds with a non-zero
exit and lets the restart policy retry, instead of looping forever and pretending
everything is fine.

---

## 7. What this project does instead

| Prohibited pattern | What is done here |
|---|---|
| `tail -f /dev/null`, `sleep infinity` | `exec nginx -g "daemon off;"` / `exec php-fpm84 -F` / `exec mariadbd --user=mysql` — the daemon is PID 1 |
| `while true; do …; done` to stay up | `restart: unless-stopped` handles crashes; the daemon runs in the foreground |
| `sleep 10` to wait for the database | `HEALTHCHECK` + `depends_on: condition: service_healthy` |
| Unbounded retry loops | Bounded 60-attempt wait that exits non-zero and lets the restart policy retry |
| A shell left in front of the daemon | `exec` replaces the shell, so no zombie shell remains |

Verified automatically, on every run:

- `tests/compliance.sh` **S06** greps the Dockerfiles, entrypoints and compose file
  for `tail -f`, `sleep infinity`, `while true`, `while :;` and long `sleep`s.
- `tests/compliance.sh` **S18** asserts every entrypoint's last line is `exec …`.
- `tests/compliance.sh` **R10** asserts PID 1 is `nginx` / `php-fpm84` / `mariadbd`
  inside the running containers.
- `tests/todo.sh` **T20** demonstrates the failure empirically: it builds a throwaway
  image whose entrypoint is `tail -f /dev/null`, kills the service inside it, and
  shows the container still reporting healthy — then shows this project's containers
  restarting correctly under the same treatment.

---

## References

- [Dockerfile reference — ENTRYPOINT, CMD, HEALTHCHECK](https://docs.docker.com/reference/dockerfile/)
- [`docker container stop` — signal behaviour](https://docs.docker.com/reference/cli/docker/container/stop/)
- [`docker container run` — `--init`](https://docs.docker.com/reference/cli/docker/container/run/#init)
- [Run multiple processes in a container](https://docs.docker.com/engine/containers/multi-service_container/)
- [Start containers automatically — restart policies](https://docs.docker.com/engine/containers/start-containers-automatically/)
- [Control startup order in Compose](https://docs.docker.com/compose/how-tos/startup-order/)
- [Docker and the PID 1 zombie reaping problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)
