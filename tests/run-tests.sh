#!/bin/bash
# Tests that need NO root and touch nothing on the system: script syntax, the diagnosis classifier and the patch shape.
# They do NOT test the download, the build or the installation.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { echo "  OK    $*"; }
bad() { echo "  FAIL  $*"; fail=1; }

echo "== Syntax"
for f in scripts/i915-patch-rebuild.sh scripts/i915-patch-status.sh scripts/i915-patch-remove.sh scripts/install.sh \
         diagnose/diagnose.sh diagnose/flicker-debug-on.sh diagnose/flicker-debug-off.sh tests/run-tests.sh; do
  bash -n "$f" 2>/dev/null && ok "bash -n $f" || bad "bash -n $f"
done
sh -n scripts/i915-patch-hook.sh 2>/dev/null && ok "sh -n scripts/i915-patch-hook.sh (the hook runs under sh)" || bad "sh -n scripts/i915-patch-hook.sh"
if command -v shellcheck >/dev/null; then
  shellcheck -S error scripts/*.sh diagnose/*.sh >/dev/null 2>&1 && ok "shellcheck (errors only)" || bad "shellcheck"
fi

echo "== Diagnosis (sample logs)"
check() { # file expected_exit_code
  bash diagnose/diagnose.sh --file "tests/fixtures/$1" >/dev/null 2>&1; local got=$?
  [ "$got" = "$2" ] && ok "$1 -> $got" || bad "$1 -> $got (expected $2)"
}
check signature-match.log 0
check signature-match-2lanes.log 0
check different-symptom.log 5
check no-retrain.log 1
check no-debug.log 3

echo "== The patch applies without fuzz to a stand-in file with the same function shape (NOT to real kernel source)"
tmp=$(mktemp -d); mkdir -p "$tmp/drivers/gpu/drm/i915/display"
cat > "$tmp/drivers/gpu/drm/i915/display/intel_dp.c" <<'EOF'
static bool
intel_dp_needs_link_retrain(struct intel_dp *intel_dp)
{
	if (intel_dp->link.retrain_disabled)
		return false;

	if (intel_dp->link.seq_train_failures)
		return true;

	/* Retrain if link not ok */
	return !intel_dp_link_ok(intel_dp, link_status) &&
		!intel_psr_link_ok(intel_dp);
}
EOF
( cd "$tmp" && patch -p1 -F0 --dry-run -s < "$OLDPWD/scripts/i915-ignore-interlane-align-edp.patch" ) >/dev/null 2>&1 && ok "the patch applies" || bad "the patch does not apply"
[ -n "$tmp" ] && rm -rf --one-file-system -- "$tmp"

[ "$fail" = 0 ] && echo && echo "ALL OK" || { echo; echo "FAILURES"; exit 1; }
