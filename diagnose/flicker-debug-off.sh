#!/bin/bash
# Removes the detailed display-driver logging added by flicker-debug-on.sh and regenerates the GRUB menu.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run it with sudo"; exit 1; }
command -v update-grub >/dev/null && [ -d /etc/default/grub.d ] \
  || { echo "This helper is for Debian/Ubuntu GRUB only. Remove 'drm.debug=0x106 log_buf_len=32M' from your kernel command line by hand." >&2; exit 1; }
F=/etc/default/grub.d/90-flicker-debug.cfg
if [ -f "$F" ]; then rm -v "$F"; else echo "$F did not exist (nothing to remove)."; fi
update-grub
echo "Done. Reboot to go back to normal logging."
