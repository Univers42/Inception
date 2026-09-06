# Bonus — FTP access to the WordPress site volume.
#
# pure-ftpd rather than vsftpd. vsftpd was tried first and works for ordinary
# clients, but on Alpine it dies under rapid connect/disconnect — the pattern a
# port scan produces — measured at 3 to 5 crashes per 60 abrupt closes even
# with isolate=NO and one_process_model ruled out. The restart policy hid it as
# a climbing RestartCount. pure-ftpd survived the identical test with zero
# restarts, so it is the one that ships.
FROM alpine:3.23

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-ftp,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add pure-ftpd \
    && rm /etc/apk/cache \
    && mkdir -p /var/www/html \
    # pure-ftpd authenticates against /etc/passwd, and refuses an account whose
    # shell is not in /etc/shells — even one that must never get a shell.
    && echo /sbin/nologin >> /etc/shells \
    # The FTP account shares uid/gid 65534 with `nobody`, which owns every file
    # WordPress writes. Two names for one uid is ordinary Unix, and it is what
    # makes this work without chmod -R g+w across ~2600 files: the FTP user IS
    # the owner, so reads and writes need no permission juggling and cannot
    # drift out of step with php-fpm.
    && echo 'ftpuser:x:65534:65534:FTP access to the WordPress volume:/var/www/html:/sbin/nologin' >> /etc/passwd

COPY conf/pure-ftpd.conf /etc/pure-ftpd.conf
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 21 21000-21010

# Reads the listening socket from /proc instead of opening a connection: a
# healthcheck should observe the daemon, not exercise it.
HEALTHCHECK --interval=15s --timeout=5s --start-period=5s --start-interval=1s --retries=3 \
    CMD ["sh", "-c", "netstat -ltn 2>/dev/null | grep -q ':21 ' && pgrep pure-ftpd >/dev/null"]

# The shell that runs this container's scripts: the entrypoint, the
# healthcheck's `sh -c`, whatever `docker exec ... sh` is asked. `make setup`
# drops the static shell the host was built with into srcs/shell/ when it has
# one (hellish, in the born2root guest), and /bin/sh becomes that; with nothing
# there, busybox's sh stays. Last, so every package script above ran under the
# shell it was written for.
COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ ! -x /usr/local/lib/inception-shell/sh ] || ln -sf /usr/local/lib/inception-shell/sh /bin/sh

ENTRYPOINT ["entrypoint.sh"]
