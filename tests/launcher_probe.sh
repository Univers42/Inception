#!/bin/sh
# tests/launcher_probe.sh -- can the shell running this file interpret the
# project's scripts? The Makefile runs `<candidate> tests/launcher_probe.sh`
# for each candidate launcher with no shell in between (make execs a command
# line without metacharacters directly), and takes the first that prints
# `INC_SH=<absolute path of the shell running this>`. Anything that is not a
# POSIX shell -- a sub-make, an editor, zsh (which is not one unless told so,
# and aborts on the first unmatched glob) -- prints nothing.
[ -z "${ZSH_VERSION:-}" ] || exit 0
a=1; f() { [ "$a" = 1 ]; }; f || exit 0
me=$(readlink /proc/$$/exe 2>/dev/null)
[ -n "$me" ] && [ -x "$me" ] || exit 0
printf 'INC_SH=%s\n' "$me"
