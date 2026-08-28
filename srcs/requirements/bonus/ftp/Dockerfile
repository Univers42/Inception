# Bonus — FTP access to the WordPress site volume.
FROM alpine:3.23

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-ftp,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add vsftpd \
    && rm /etc/apk/cache \
    # secure_chroot_dir: vsftpd needs an empty, non-writable directory to
    # chroot into while it is still privileged. It refuses to start without it.
    && mkdir -p /var/lib/vsftpd/empty \
    # vsftpd checks the login shell against /etc/shells and rejects the user if
    # it is absent — even though this account must never get a shell.
    && echo /sbin/nologin >> /etc/shells \
    # The FTP account shares uid/gid 65534 with `nobody`, which owns every file
    # WordPress writes. Two names for one uid is ordinary Unix, and it is what
    # makes this work without chmod -R g+w over the whole site: the FTP user IS
    # the owner, so reads and writes need no permission juggling and cannot
    # drift out of step with php-fpm.
    && echo 'ftpuser:x:65534:65534:FTP access to the WordPress volume:/var/www/html:/sbin/nologin' >> /etc/passwd

COPY conf/vsftpd.conf /etc/vsftpd/vsftpd.conf
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 21 21000-21010

# Check the listening socket WITHOUT opening a connection.
#
# The obvious `nc -z 127.0.0.1 21` connects and then drops the socket abruptly,
# and vsftpd on Alpine segfaults on that abrupt close — so the healthcheck
# itself was killing the daemon every 10 seconds and the restart policy kept
# reviving it (49 restarts before this was traced). Real FTP sessions, which
# close politely with QUIT, are unaffected.
#
# netstat reads /proc and touches nothing, so it observes the daemon instead of
# perturbing it, and still fails if vsftpd has stopped listening.
HEALTHCHECK --interval=15s --timeout=5s --start-period=5s --start-interval=1s --retries=3 \
    CMD ["sh", "-c", "netstat -ltn 2>/dev/null | grep -q ':21 ' && pgrep vsftpd >/dev/null"]

ENTRYPOINT ["entrypoint.sh"]
