# How the cause was found

Everything below was measured on one machine: MSI Prestige 16Studio A13VF, Intel Raptor Lake-P `8086:a7a0` (subsystem `1462:13c3`) driving the internal eDP panel AUO `B160QAN02.K` (2560×1600, 60 Hz and 165.04 Hz fixed modes, 10 bpc), NVIDIA RTX 4060 Max-Q in on-demand mode, Ubuntu 26.04, kernel `7.0.0-42-generic`, GNOME/mutter on Wayland.

## Symptom

After boot, on the login screen and then the desktop, the internal panel blanks and comes back ~5–11 times, then stops. It is not visible in the firmware setup screens. It can also be provoked by switching 60 Hz ↔ 165 Hz.

## Things that made no difference

`i915.enable_psr=0`, `i915.enable_panel_replay=0`, `i915.enable_dc=0` (and the panel does not even advertise PSR/Panel Replay); link rate forced to HBR2; backlight at 25 %; FBC disabled; the NVIDIA GPU kept awake (runtime PM off); 60 Hz vs 165 Hz; ambient light sensor; NVIDIA driver/packages/PCIe errors/firmware (all healthy).

## Capturing it

Boot with `drm.debug=0x106 log_buf_len=32M` (see `diagnose/flicker-debug-on.sh`) and read `journalctl -k -b`. In a flickering boot (one cycle, repeated every 3.07 s, 12 trainings / 11 retrains, 34 s from the first to the last training):

```
Link Training passed at link rate = 810000, lane count = 4      # 8.1 Gbps, TPS3 (the sink has no TPS4)
  DPCD 0x202 right after EQ:  77 77 81 00 00 00                 # all lanes locked, INTERLANE_ALIGN_DONE = 1
intel_edp_backlight_on
... +2.02 s ...
ln0_1:0x77 ln2_3:0x77 align:0x80 sink:0x1 adj_req0_1:0x0 adj_req2_3:0x0
8b/10b link not ok, retraining
retraining link (forced no)   -> full modeset: backlight off, panel power off/on (~1 s), train again
```

All four lanes report CR/EQ/symbol lock and there are no adjust requests; only `INTERLANE_ALIGN_DONE` (DPCD `0x204` bit 0) is clear at the **2 s post-training link recheck** ("drm/i915/dp: Recheck link state after modeset", Imre Deak, 2024). In a non-flickering boot there was 1 training and 0 retrains.

## A/B tests on a running system

Same 8–12 mode changes each (60 Hz ↔ 165 Hz via `gdctl`), `drm.debug` on, counting how many end in a retrain:

| Variable changed | Modesets ending in a retrain |
|---|---|
| baseline (auto link, HBR3 ×4, 10 bpc) | 7/12, 7/10, 6/10 |
| link forced to HBR2 (the link settled at 24 and at 18 bits per pixel instead of 30) | 4/8, 5/8 |
| backlight 25 % | 6/10 |
| FBC disabled | 7/10 |
| NVIDIA dGPU kept awake | 5/10 |
| **with the patch** | **0/12** |

After the patch: 3 consecutive boots with 1 link training and 0 retrains each, and the picture is clean — which suggests the panel is not actually losing alignment and its TCON reports `INTERLANE_ALIGN_DONE = 0` during normal operation.

## The sink

```
DPCD 0x000: 14 1e 44 41 00 00 01 c0 02 00 02 00 00 0b 80   (DPCD 1.4, max 8.1G, 4 lanes, enhanced framing)
eDP  0x700: 04 9b 86 04 1e     sink rates: 162000 216000 243000 270000 324000 432000 540000 810000
0x400 (sink OUI / device id / HW/FW rev): 38 ec 11 00 00 00 00 00 00 00 00 00
```

## The patch

One block in `intel_dp_needs_link_retrain()`: for eDP, OR `DP_INTERLANE_ALIGN_DONE` into the local copy of the link status before `intel_dp_link_ok()`. The per-lane CR/EQ/symbol-lock bits are still checked. It does **not** touch link training itself.

## Not established

* Whether older kernels (before the post-training recheck was introduced, in 2024) would avoid the problem was never tested.
* Whether other machines/panels with this signature exist. (The signature classifier in `diagnose/diagnose.sh` exists so that people can find out before applying anything.)
* Why the retrain loop stops by itself after 5-11 cycles (and why it is intermittent across boots) is not understood.
* A proper fix would be a DPCD/panel quirk upstream, keyed on device/subsystem/sink OUI, like the CH7511 one (different hardware).
