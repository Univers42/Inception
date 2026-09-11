#!/bin/hellish
# shellcheck shell=sh
[ -z "${ZSH_VERSION:-}" ] || exit 0
a=1; f() { [ "$a" = 1 ]; }; f || exit 0
me=$(readlink /proc/$$/exe 2>/dev/null)
[ -n "$me" ] && [ -x "$me" ] || exit 0
printf 'INC_SH=%s\n' "$me"
