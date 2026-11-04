#!/bin/bash
# Shows, for every installed kernel, whether it has the patched i915 and the result of the last rebuild.
for d in /lib/modules/*/; do
  k=$(basename "$d"); [ -d "$d/kernel/drivers/gpu/drm/i915" ] || continue
  o="$d/updates/i915.ko"
  if [ -f "$o" ]; then
    st="PATCHED (srcversion $(modinfo -F srcversion "$o" 2>/dev/null))"
  else st="not patched (stock i915: the flicker may be back)"; fi
  run=""; [ "$k" = "$(uname -r)" ] && run="  <- running (loaded: $(cat /sys/module/i915/srcversion 2>/dev/null))"
  echo "$k: $st$run"
  if [ -f "/var/lib/i915-patch/status-$k" ]; then
    read -r s ts rest < "/var/lib/i915-patch/status-$k"
    echo "    last rebuild: $s ${rest:-} ($(date -d "@$ts" '+%F %T' 2>/dev/null))"
  fi
done
[ -e /var/lib/i915-patch/disabled ] && echo "NOTE: automatic rebuild is DISABLED (/var/lib/i915-patch/disabled exists)"
echo; echo "Last log lines:"; tail -5 /var/log/i915-patch.log 2>/dev/null || true
exit 0
