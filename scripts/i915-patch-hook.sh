#!/bin/sh
# /etc/kernel/postinst.d/zz-i915-patch   ($1 = version of the kernel that was just installed)
# Starts the i915 patch rebuild for that kernel IN THE BACKGROUND. It never blocks apt and never makes it fail.
[ -x /usr/local/sbin/i915-patch-rebuild ] || exit 0
[ -e /var/lib/i915-patch/disabled ] && exit 0
case "$1" in
  *-generic) ;;
  *) exit 0 ;;
esac
if command -v systemd-run >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemd-run --no-block --quiet --collect --unit="i915-patch-build-$1" \
    --property=Nice=19 --property=IOSchedulingClass=idle --property=RuntimeMaxSec=3h \
    /usr/local/sbin/i915-patch-rebuild "$1" >/dev/null 2>&1 \
    || logger -t i915-patch "could not start the rebuild for $1" 2>/dev/null || true
else
  setsid nohup /usr/local/sbin/i915-patch-rebuild "$1" </dev/null >/dev/null 2>&1 &
fi
exit 0
