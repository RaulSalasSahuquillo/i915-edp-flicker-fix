#!/bin/bash
# i915-patch-rebuild [kernel-version]
#
# Rebuilds the patched i915 module (ignore INTERLANE_ALIGN_DONE on eDP) for ONE kernel, from the EXACT source of that
# kernel (Ubuntu source package, verified by apt and by hash), and installs it as an override in
# /lib/modules/<kver>/updates/i915.ko ONLY if every validation passes. If anything fails it installs nothing: that kernel
# keeps its stock i915 (the flicker may come back, but a failed run never removes the stock driver).
# Caveat: an override installed earlier will not load if Secure Boot/lockdown is enabled afterwards.
#
# Accepted environment variables: BUILD_ONLY=1 (build and validate, install nothing; still run it as root, because STATE,
# CACHE and LOG live under /var), FORCE=1, KEEP=1.
# Paths (STATE, CACHE, LOG, PATCH, MODROOT) and SETTLE/WAIT_HEADERS are honoured only with I915_PATCH_TEST=1.
set -Eeuo pipefail
umask 022
export LC_ALL=C PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
unset TAR_OPTIONS GZIP MAKEFLAGS MAKEOVERRIDES MFLAGS KBUILD_OUTPUT KBUILD_EXTRA_SYMBOLS APT_CONFIG CC LD CROSS_COMPILE ARCH LD_PRELOAD LD_LIBRARY_PATH TMPDIR

KVER="${1:-$(uname -r)}"
[[ "$KVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[a-z0-9-]+$ ]] || { echo "invalid kernel version" >&2; exit 1; }
BUILD_ONLY="${BUILD_ONLY:-0}"; FORCE="${FORCE:-0}"; KEEP="${KEEP:-0}"
if [ "${I915_PATCH_TEST:-0}" = 1 ]; then
  STATE="${STATE:?}"; CACHE="${CACHE:?}"; LOG="${LOG:?}"; PATCH="${PATCH:?}"; MODROOT="${MODROOT:-/lib/modules}"
  WAIT_HEADERS="${WAIT_HEADERS:-1800}"; SETTLE="${SETTLE:-0}"
else
  STATE=/var/lib/i915-patch; CACHE=/var/cache/i915-patch; LOG=/var/log/i915-patch.log
  PATCH=/usr/local/share/i915-patch/i915-ignore-interlane-align-edp.patch; MODROOT=/lib/modules
  WAIT_HEADERS=1800; SETTLE=20
fi

[ ! -L "$LOG" ] || { echo "the log path is a symlink; refusing to write to it" >&2; exit 1; }
mkdir -p "$STATE" "$CACHE" "$(dirname "$LOG")"
log()   { echo "$(date '+%F %T') [$KVER] $*" | tee -a "$LOG" >&2; }
status(){ echo "$1 $(date +%s) ${2:-}" > "$STATE/status-$KVER" 2>/dev/null || true; }
fail()  { log "ABORT: $*"; status failed "$*"; exit 1; }
trap 'rc=$?; log "UNEXPECTED ERROR (rc=$rc) line $LINENO: $BASH_COMMAND"; status failed "unexpected error line $LINENO"' ERR

# An UNSIGNED module will not load with Secure Boot / lockdown, and modprobe does not fall back to the stock one.
secure_boot_active() {
  local sb
  sb=$(od -An -tu1 -j4 -N1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | tr -d ' ' || true)
  grep -qE '\[(integrity|confidentiality)\]' /sys/kernel/security/lockdown 2>/dev/null || [ "$sb" = 1 ]
}

[ "$BUILD_ONLY" = 1 ] || [ "$(id -u)" -eq 0 ] || fail "run as root (or with BUILD_ONLY=1)"
[ -f "$PATCH" ] || fail "patch file not found: $PATCH"
[ ! -e "$STATE/disabled" ] || { log "automatic rebuild is disabled ($STATE/disabled exists)"; exit 0; }

# One job at a time (several kernels can be installed in the same apt transaction)
exec 9>"$STATE/lock"; flock -w 7200 9 || fail "could not get the lock"
[ -e "$CACHE/.i915-patch-cache" ] || touch "$CACHE/.i915-patch-cache"
# Leftovers of interrupted jobs (SIGKILL, power cut): safe to delete because we hold the lock
find "$CACHE" -mindepth 1 -maxdepth 1 -type d -name 'work.*' -exec rm -rf --one-file-system -- {} + 2>/dev/null || true

# Refuse early, before any download or build, on a machine where the override could never load
if [ "$BUILD_ONLY" != 1 ] && secure_boot_active; then
  log "Secure Boot/lockdown is ACTIVE: an unsigned i915 would not load; nothing to do"; status skipped "secure boot/lockdown"; exit 0
fi

STOCK="$MODROOT/$KVER/kernel/drivers/gpu/drm/i915/i915.ko.zst"; [ -f "$STOCK" ] || STOCK="${STOCK%.zst}"
if [ ! -f "$STOCK" ]; then log "this kernel ships no i915 module (nothing to do)"; status ok "no i915"; exit 0; fi
DEST="$MODROOT/$KVER/updates/i915.ko"
BUILD="$MODROOT/$KVER/build"
STOCK_SV=$(modinfo -F srcversion "$STOCK")
STOCK_SHA=$(sha256sum "$STOCK" | cut -d' ' -f1)

# Boot-time retries: do not insist if the last run failed or was skipped less than 6 h ago
if [ "${I915_PATCH_CATCHUP:-0}" = 1 ] && [ -f "$STATE/status-$KVER" ]; then
  read -r st ts _ < "$STATE/status-$KVER" || true
  if { [ "${st:-}" = failed ] || [ "${st:-}" = skipped ]; } && [ $(( $(date +%s) - ${ts:-0} )) -lt 21600 ]; then
    log "recent $st result; not retrying yet"; exit 0
  fi
fi

# Boot-time retries: ONLY for the newest kernel (older ones, e.g. the previous kernel, are deliberately left unpatched:
# they are the way out if the patch ever causes trouble)
if [ "${I915_PATCH_CATCHUP:-0}" = 1 ]; then
  newest=$(ls -1 "$MODROOT" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-generic$' | sort -V | tail -1 || true)
  [ "$KVER" = "$newest" ] || { log "boot retry applies only to the newest kernel ($newest); exiting"; exit 0; }
fi

# Valid override for THIS stock module already installed: nothing to do
if [ -f "$DEST" ] && [ "$FORCE" != 1 ] && [ "$BUILD_ONLY" != 1 ]; then
  if [ "$(modinfo -F srcversion "$DEST")" != "$STOCK_SV" ] \
     && [ "$(modinfo -F vermagic "$DEST")" = "$(modinfo -F vermagic "$STOCK")" ] \
     && [ -f "$STATE/built-$KVER" ] && [ "$(cat "$STATE/built-$KVER")" = "$STOCK_SHA" ]; then
    if [ "$(modinfo -k "$KVER" -n i915)" = "$DEST" ]; then log "a valid override for this stock module is already installed; nothing to do"; status ok "already installed"; exit 0; fi
    depmod -a "$KVER"; log "valid override was not indexed; ran depmod"; status ok "reindexed"; exit 0
  fi
  if [ -f "$STATE/built-$KVER" ]; then log "an override exists but does not match the current stock module; rebuilding"; fi
fi
# Never overwrite a module this tool did not install (no ownership marker) unless asked to
if [ -f "$DEST" ] && [ ! -f "$STATE/built-$KVER" ] && [ "$FORCE" != 1 ] && [ "$BUILD_ONLY" != 1 ]; then
  fail "$DEST exists but was not installed by this tool; refusing to overwrite it (use FORCE=1 to replace it)"
fi

# From here on there is real work: mark it (an interrupted run then shows up in i915-patch-status)
status running "started"

# Wait until ALL the kernel headers are installed (apt may still be working)
hdr_ready() {
  [ -f "$BUILD/Module.symvers" ] && [ -f "$BUILD/.config" ] || return 1
  [ "${I915_PATCH_TEST:-0}" = 1 ] && return 0
  local p; for p in "linux-headers-$KVER" "linux-headers-${KVER%-generic}"; do
    [ "$(dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null || echo none)" = installed ] || return 1
  done
}
t=0; while ! hdr_ready; do
  [ "$t" -lt "$WAIT_HEADERS" ] || fail "kernel headers for $KVER are not (completely) installed after ${WAIT_HEADERS}s (install linux-headers-$KVER)"
  sleep 10; t=$((t+10))
done
sleep "$SETTLE"

# Exact source package of this kernel
SRCPKG=""; SRCVER=""
read -r SRCPKG SRCVER < <(dpkg-query -W -f='${source:Package} ${source:Version}\n' "linux-modules-$KVER" 2>/dev/null) || true
[ -n "$SRCVER" ] || fail "linux-modules-$KVER is not installed (cannot find its source package)"
[ "$SRCPKG" = "linux" ] || fail "unsupported kernel: its source package is '$SRCPKG' (only the 'linux' source package is supported, i.e. stock -generic kernels; HWE/OEM/cloud kernels are not)"
[[ "$SRCVER" =~ ^[0-9][0-9A-Za-z.+~-]*$ ]] || fail "invalid source version: '$SRCVER'"
log "kernel $KVER <- source linux $SRCVER"

DL="$CACHE/$SRCVER"; mkdir -p "$DL"
WORK="$(mktemp -d "$CACHE/work.XXXXXX")"
cleanup() { [ "$KEEP" = 1 ] || rm -rf --one-file-system -- "$WORK"; }; trap cleanup EXIT

# --- 1) Download the source with a private apt setup (does not touch /etc/apt), signed with the Ubuntu keyring ---
have_src() {   # the orig tarball, the diff and the dsc REALLY exist (no broken links, no empty files)
  local o=0 f
  for f in "$DL"/linux_*.orig.tar.*; do [ -s "$f" ] && o=1; done
  [ "$o" = 1 ] && [ -s "$DL/linux_$SRCVER.diff.gz" ] && [ -s "$DL/linux_$SRCVER.dsc" ]
}
if ! have_src; then
  find "$DL" -maxdepth 1 -type f -name 'linux_*' -delete   # discard incomplete or broken leftovers
  CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-}"); [ -n "$CODENAME" ] || fail "cannot determine the distribution codename"
  KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg; [ -f "$KEYRING" ] || fail "missing $KEYRING"
  A="$WORK/apt"; mkdir -p "$A/lists/partial" "$A/cache/archives/partial"
  {
    echo "deb-src [signed-by=$KEYRING] http://archive.ubuntu.com/ubuntu $CODENAME main restricted"
    echo "deb-src [signed-by=$KEYRING] http://archive.ubuntu.com/ubuntu $CODENAME-updates main restricted"
    echo "deb-src [signed-by=$KEYRING] http://security.ubuntu.com/ubuntu $CODENAME-security main restricted"
  } > "$A/sources.list"
  APT=(-o Dir::Etc::sourcelist="$A/sources.list" -o Dir::Etc::sourceparts=/dev/null -o Dir::State::lists="$A/lists"
       -o Dir::Cache="$A/cache" -o APT::Sandbox::User="$(id -un)")
  log "downloading the source of linux $SRCVER (~260 MB)"
  apt-get "${APT[@]}" -qq update >>"$LOG" 2>&1 || fail "apt update (sources) failed"
  ( cd "$DL" && apt-get "${APT[@]}" -qq source --download-only "linux=$SRCVER" >>"$LOG" 2>&1 ) || fail "could not download linux=$SRCVER"
fi
have_src || fail "the downloaded sources are incomplete in $DL"
DSC="$DL/linux_$SRCVER.dsc"
ORIG=""; for f in "$DL"/linux_*.orig.tar.*; do [ -s "$f" ] && ORIG="$f" && break; done
[ -n "$ORIG" ] || fail "original tarball not found"
# Check hashes against the .dsc (apt already verified it against the signed index): EVERY file we use must be verified
python3 -I - "$DSC" "$DL" "$(basename "$ORIG")" "linux_$SRCVER.diff.gz" <<'EOF' || fail "source checksums do not match the .dsc"
import hashlib,sys,os,re
dsc,dl=sys.argv[1:3]; need=set(sys.argv[3:5])
txt=open(dsc,encoding='utf-8',errors='replace').read()
m=re.search(r'^Checksums-Sha256:\n((?:[ \t].*\n?)+)',txt,re.M)
if not m: sys.exit("no Checksums-Sha256")
seen=set()
for l in m.group(1).strip().splitlines():
    h,sz,name=l.split()
    p=os.path.join(dl,name)
    if name in need:
        if not os.path.exists(p): sys.exit("missing "+name)
        d=hashlib.sha256(open(p,'rb').read()).hexdigest()
        if d!=h or os.path.getsize(p)!=int(sz): sys.exit("checksum mismatch: "+name)
        seen.add(name)
if not need<=seen: sys.exit("not every needed file was verified")
EOF
log "OK: source checksums verified"

# --- 2) Extract only what is needed and apply Ubuntu's patches (identical to the installed kernel) ---
TREE="$WORK/tree"; mkdir -p "$TREE"
tar -xf "$ORIG" -C "$TREE" --strip-components=1 --no-same-owner --no-same-permissions --no-overwrite-dir \
  --wildcards 'linux-*/drivers/gpu/drm' 'linux-*/drivers/platform/x86/intel_ips.h' \
  || fail "could not extract the sources"
gzip -dc "$DL/linux_$SRCVER.diff.gz" > "$WORK/ubuntu.diff"
python3 -I - "$WORK/ubuntu.diff" "$WORK/drm.diff" <<'EOF'
import sys
src,dst=sys.argv[1:3]
lines=open(src,encoding='utf-8',errors='surrogateescape').read().split('\n')
keep=False; out=[]; i=0
while i<len(lines):
    l=lines[i]
    if l.startswith('--- ') and i+1<len(lines) and lines[i+1].startswith('+++ '):
        p=lines[i+1].split('\t')[0][4:]
        keep=p.split('/',1)[1].startswith(('drivers/gpu/drm/','drivers/platform/x86/intel_ips.h')) if '/' in p else False
    if keep: out.append(l)
    i+=1
open(dst,'w',encoding='utf-8',errors='surrogateescape').write('\n'.join(out)+'\n')
EOF
( cd "$TREE" && patch -p1 -s --no-backup-if-mismatch < "$WORK/drm.diff" ) >>"$LOG" 2>&1 || fail "could not apply Ubuntu's diff to the sources"
[ -z "$(find "$TREE" -name '*.rej' | head -1)" ] || fail "rejected hunks while applying Ubuntu's diff"

# --- 3) Apply OUR patch without fuzz; if the code changed, abort and install nothing ---
( cd "$TREE" && patch -p1 -F0 --dry-run -s < "$PATCH" ) >>"$LOG" 2>&1 \
  || fail "the patch no longer applies cleanly to the sources of $SRCVER (the i915 code changed): it needs manual review"
( cd "$TREE" && patch -p1 -F0 -s --no-backup-if-mismatch < "$PATCH" ) >>"$LOG" 2>&1 || fail "applying the patch failed"
F="$TREE/drivers/gpu/drm/i915/display/intel_dp.c"
[ "$(grep -c 'LOCAL WORKAROUND (MSI Prestige 16Studio' "$F")" = 1 ] || fail "the patch marker is not present exactly once"
grep -q 'intel_dp_is_edp(intel_dp))' "$F" || fail "the patch does not contain the expected eDP condition"
log "OK: sources prepared and patch applied without fuzz"

# --- 4) Build only i915 against THIS kernel's headers ---
mkdir -p "$WORK/inc/x/y"; ln -sfn "$TREE/drivers" "$WORK/inc/drivers"
log "building i915 (a few minutes at most)"
if ! nice -n 19 make -C "$BUILD" M="$TREE/drivers/gpu/drm/i915" KCFLAGS="-I$WORK/inc/x/y" -j"$(nproc)" modules >"$WORK/build.log" 2>&1; then
  tail -15 "$WORK/build.log" >>"$LOG"; fail "the build failed (see $LOG)"
fi
[ -f "$TREE/drivers/gpu/drm/i915/i915.ko" ] || fail "i915.ko was not produced"
cp "$TREE/drivers/gpu/drm/i915/i915.ko" "$WORK/i915.ko"; strip --strip-debug "$WORK/i915.ko"
NEW="$WORK/i915.ko"

# --- 5) Validation: same ABI as the stock i915 of THIS kernel ---
[ "$(stat -c %s "$NEW")" -lt 52428800 ] || fail "the resulting module is larger than 50 MB"
[ "$(modinfo -F vermagic "$NEW")" = "$(modinfo -F vermagic "$STOCK")" ] || fail "vermagic differs from the stock module"
[ "$(modinfo -F srcversion "$NEW")" != "$STOCK_SV" ] || fail "the module is identical to the stock one (the patch had no effect)"
modinfo -F alias "$NEW" | grep 'pci:' >/dev/null || fail "the module has no PCI aliases"   # sanity check only: it does not restrict hardware
modprobe --dump-modversions "$STOCK" 2>/dev/null | sort > "$WORK/orig.crc" || true
if [ ! -s "$WORK/orig.crc" ]; then zstd -dqf "$STOCK" -o "$WORK/stock.ko" 2>/dev/null || cp "$STOCK" "$WORK/stock.ko"; modprobe --dump-modversions "$WORK/stock.ko" | sort > "$WORK/orig.crc"; fi
modprobe --dump-modversions "$NEW" | sort > "$WORK/new.crc"
[ -s "$WORK/orig.crc" ] && [ -s "$WORK/new.crc" ] || fail "could not read the modversions"
diff -q "$WORK/orig.crc" "$WORK/new.crc" >/dev/null || fail "symbol CRCs do NOT match the stock i915 (it would not load)"
NEW_SV=$(modinfo -F srcversion "$NEW")
log "OK: validated ($(wc -l < "$WORK/new.crc") identical CRCs, identical vermagic, srcversion $NEW_SV)"

if [ "$BUILD_ONLY" = 1 ]; then
  echo "BUILD_ONLY: module built and validated, srcversion=$NEW_SV (stock=$STOCK_SV). Nothing was installed."
  if [ "$KEEP" = 1 ]; then cp "$NEW" "$CACHE/i915.$KVER.ko"; echo "copy: $CACHE/i915.$KVER.ko"; fi
  status ok "build-only"; exit 0
fi

# --- 6) Guards before installing ---
[ ! -e "$STATE/disabled" ] || { log "disabled while building; not installing"; status skipped "disabled"; exit 0; }
if secure_boot_active; then log "Secure Boot/lockdown is ACTIVE: an unsigned i915 would not load; installing nothing"; status skipped "secure boot/lockdown"; exit 0; fi

# --- 7) Atomic install with fsync and rollback (restores the previous override if there was one) ---
mkdir -p "$(dirname "$DEST")"
PREV=""; if [ -f "$DEST" ]; then PREV="$WORK/dest.prev"; cp -p "$DEST" "$PREV"; fi
rollback() {
  if [ -n "$PREV" ] && [ -f "$PREV" ]; then install -m 0644 "$PREV" "$DEST" || rm -f "$DEST"; else rm -f "$DEST"; fi
  rm -f "$DEST.new"; depmod -a "$KVER" || true
}
if ! { install -m 0644 "$NEW" "$DEST.new" && sync "$DEST.new" && cmp -s "$NEW" "$DEST.new" \
       && mv -f "$DEST.new" "$DEST" && sync -f "$(dirname "$DEST")" \
       && depmod -a "$KVER" && sync -f "$MODROOT/$KVER" \
       && [ "$(modinfo -k "$KVER" -n i915)" = "$DEST" ]; }; then
  rollback; fail "the atomic install failed; rolled back"
fi
install -m 0644 "$NEW" "$STATE/$KVER-i915.ko" 2>/dev/null || true
echo "$STOCK_SHA" > "$STATE/built-$KVER"
status ok "srcversion=$NEW_SV source=$SRCVER"
log "INSTALLED: override for $KVER (srcversion $NEW_SV). It takes effect the next time that kernel boots."

# --- 8) Cleanup limited to what this script creates ---
if [ -e "$CACHE/.i915-patch-cache" ]; then
  for d in "$CACHE"/[0-9]*/; do
    [ -d "$d" ] || continue; b=$(basename "$d")
    [ "$b" = "$SRCVER" ] && continue
    [[ "$b" =~ ^[0-9][0-9A-Za-z.+~-]*$ ]] && rm -rf --one-file-system -- "$d"
  done
fi
# Leftovers of uninstalled kernels
for f in "$MODROOT"/*/updates/i915.ko; do
  [ -f "$f" ] || continue; k=$(basename "$(dirname "$(dirname "$f")")")
  [[ "$k" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[a-z0-9-]+$ ]] || continue
  [ -f "$STATE/built-$k" ] || continue          # only ours
  if [ ! -d "$MODROOT/$k/kernel/drivers/gpu/drm/i915" ]; then
    rm -f -- "$f" "$STATE/status-$k" "$STATE/built-$k" "$STATE/$k-i915.ko"; log "removed leftovers of uninstalled kernel: $k"
  fi
done
