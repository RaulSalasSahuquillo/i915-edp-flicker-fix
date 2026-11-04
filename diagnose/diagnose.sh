#!/bin/bash
# diagnose.sh - READ-ONLY. Checks whether the kernel log of a boot shows the signature of the bug this repo works around.
#
# Needs a boot with "drm.debug=0x106" (see diagnose/flicker-debug-on.sh) in which the screen flickered.
# Usage:  ./diagnose.sh            analyse the current boot (journalctl -k -b 0)
#         ./diagnose.sh -1         analyse the previous boot
#         ./diagnose.sh --file F   analyse a saved log (journalctl -k -o short-monotonic)
#
# THE SIGNATURE: the eDP link trains fine and ~2 s later the kernel decides the link is bad and retrains it (with a full
# panel power cycle), BUT all lanes are still locked (0x77) and only the INTERLANE_ALIGN_DONE bit of DPCD byte 0x204 is
# missing (align:0x80 / 0x00).
#
# Exit codes:  0 = THE SIGNATURE MATCHES      5 = retrains with OTHER symptoms (this fix is NOT for you)
#              1 = no retrains in that boot (expected after a successful fix)
#              3 = no drm.debug data in that boot      4 = retrains seen but no link-status dump (cannot classify)
#              2 = bad arguments, or the journal is not readable (retry with sudo)
set -uo pipefail
export LC_ALL=C
if [ "${1:-}" = "--file" ]; then
  [ -f "${2:-}" ] || { echo "No such file: '${2:-}'" >&2; exit 2; }
  SRC=$(cat "$2")
else
  BOOT="${1:-0}"; [[ "$BOOT" =~ ^-?[0-9]+$ ]] || { echo "Usage: $0 [N | --file FILE]" >&2; exit 2; }
  SRC=$(journalctl -k -b "$BOOT" --no-pager -o short-monotonic 2>&1) || true
  if printf '%s\n' "$SRC" | head -n 3 | grep -qiE 'not seeing messages|no journal files|insufficient permissions'; then
    echo "Cannot read the kernel journal as a normal user. Try:  sudo $0 $*" >&2; exit 2
  fi
fi
printf '%s\n' "$SRC" | python3 -I -c '
import re,sys
txt=sys.stdin.read()
lines=txt.split("\n")
drm=sum(1 for l in lines if "[drm:" in l)
ts=lambda l:(lambda m: float(m.group(1)) if m else None)(re.match(r"^\[\s*([0-9.]+)\]",l))
train=[(ts(l),re.search(r"link rate = (\d+), lane count = (\d+)",l).groups()) for l in lines if "Link Training passed" in l and re.search(r"link rate = (\d+), lane count = (\d+)",l)]
notok=[l for l in lines if "8b/10b link not ok, retraining" in l]
retr=[ts(l) for l in lines if "intel_dp_retrain_link" in l]
dumps=[]
for l in lines:
    m=re.search(r"intel_dp_dump_link_status.*ln0_1:0x([0-9a-f]+) ln2_3:0x([0-9a-f]+) align:0x([0-9a-f]+) sink:0x([0-9a-f]+) adj_req0_1:0x([0-9a-f]+) adj_req2_3:0x([0-9a-f]+)",l)
    if m: dumps.append(tuple(int(x,16) for x in m.groups()))
print("== Summary of the analysed boot")
print(f"   drm debug lines: {drm}")
print(f"   successful link trainings: {len(train)}   retrains: {len(retr)}   \"link not ok\" warnings: {len(notok)}")
if train: print(f"   link: {int(train[0][1][0])/100000:.1f} Gbps/lane x {train[0][1][1]} lanes")
if len(retr)>=3 and all(x is not None for x in retr):
    d=[round(b-a,2) for a,b in zip(retr,retr[1:]) if b-a<30]
    if d: print(f"   interval between retrains: {min(d)}-{max(d)} s")
print()
if drm<50:
    print("RESULT: NO DATA. This boot has no drm.debug logging.")
    print("  Enable it with diagnose/flicker-debug-on.sh, reboot until the screen flickers, then run this again.")
    sys.exit(3)
if not retr:
    print("RESULT: no link retrains in this boot.")
    print("  If the screen flickered in this boot, your cause is something ELSE and this workaround is not for you.")
    print("  If it did not flicker, repeat with a boot that does. (After a successful fix this is the expected result.)")
    sys.exit(1)
if not dumps:
    print("RESULT: retrains were seen but the link-status dump is missing; cannot classify them.")
    sys.exit(4)
lanes=int(train[0][1][1]) if train else 4
def lanes_ok(d):
    a,b=d[0],d[1]
    ok01=(a==0x77) if lanes>=2 else ((a&0x7)==0x7)
    ok23=True if lanes<=2 else (b==0x77 if lanes==4 else ((b&0x7)==0x7))
    return ok01 and ok23
align_clear=[not (d[2]&1) for d in dumps]; lok=[lanes_ok(d) for d in dumps]; adj0=[d[4]==0 and d[5]==0 for d in dumps]
n=len(dumps)
print(f"   of {n} link-status dumps: lanes locked={sum(lok)}  inter-lane alignment MISSING={sum(align_clear)}  no adjust requests={sum(adj0)}")
if all(lok) and all(align_clear) and all(adj0):
    print("RESULT: THE SIGNATURE MATCHES. Every lane is locked and only the INTERLANE_ALIGN_DONE bit is missing.")
    print("  This repo probably fixes your case. (It is still a local workaround: read the README before applying it.)")
    sys.exit(0)
print("RESULT: retrains with OTHER symptoms (lanes not locked, or adjust requests).")
print("  This workaround is NOT for you: ignoring the alignment bit would not fix a genuinely unstable link.")
sys.exit(5)
'
