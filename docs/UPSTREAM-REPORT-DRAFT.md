# drm/i915: eDP retrain loop (screen flicker) on MSI Prestige 16Studio A13VF — sink reports INTERLANE_ALIGN_DONE=0 at the 2 s post-training link recheck

*(Draft, not filed. Review it before sending it to <https://gitlab.freedesktop.org/drm/i915/kernel/-/issues>.)*

## Hardware / software
- Laptop: MSI Prestige 16Studio A13VF (MS-1594), BIOS E1594IMS.115 (2024-10-07), EC fw 1594EMS1.113
- GPU: Intel Raptor Lake-P Iris Xe, PCI 8086:a7a0, subsystem 1462:13c3 (i915 drives eDP-1). NVIDIA RTX 4060 Max-Q present (hybrid, PRIME on-demand) but has no connectors on the panel.
- Panel: AUO 0xdb95 "B160QAN02.K", 2560x1600, 60 Hz (650 MHz pclk) and 165.04 Hz (777.51 MHz pclk) fixed modes, EDID 1.4, 10 bpc, VRR 60–165 Hz
- Kernel: Ubuntu 7.0.0-42-generic (also 7.0.0-38). Ubuntu 26.04.1, GNOME 50.1/mutter 50.1 Wayland, GDM. Symptom also present before the 24.04→26.04 upgrade (mutter 46), same 7.0 kernel series.
- Boot params used for capture: `i915.enable_psr=0 drm.debug=0x106 log_buf_len=32M`

## Symptom
Internal panel blanks and comes back repeatedly after boot (visible on GDM login and desktop), 11 retrains in one captured boot (12 trainings between t=6.28 s and 40.1 s), then it stops by itself. Not visible in firmware/BIOS setup. Can be re-triggered on demand by changing the mode (60 Hz <-> 165 Hz): about 50-70 % of modesets end in a retrain (47/78 = 60 % over all unpatched runs below).

## What the log shows (one cycle, repeated every 3.07 s)
```
link train OK:  Link Training passed at link rate = 810000, lane count = 4   (8.1 Gbps without sink TPS4 support -> TPS3)
                post-EQ DPCD 0x202: 77 77 81 00 00 00   (lanes locked, INTERLANE_ALIGN_DONE=1)
intel_edp_backlight_on
... +2.02 s ...
intel_dp_dump_link_status: ln0_1:0x77 ln2_3:0x77 align:0x80 sink:0x1 adj_req0_1:0x0 adj_req2_3:0x0
intel_dp_link_ok: 8b/10b link not ok, retraining      (second read 1 ms later: 77 77 00 01 00 00)
intel_dp_retrain_link: retraining link (forced no)
-> full modeset: backlight off, PPS panel power off/on (~1 s), link train again ...
```
All four lanes report CR/EQ/symbol lock (0x77) and adjust requests are 0. Only INTERLANE_ALIGN_DONE (0x204 bit0) is clear at the +2 s recheck (the recheck introduced by "drm/i915/dp: Recheck link state after modeset", 2 s delay). Captured boot: 12 trainings (t=6.28 s … 40.1 s), 11 retrains; the following boot: 1 training, 0 retrains. No FIFO underruns, no AER errors, no link-training failures.

## Controlled A/B on a running system (same 8-12 mode changes each, drm.debug on)
| Variable changed (runtime) | modesets with retrain |
|---|---|
| baseline (auto link, HBR3 4 lanes, 10 bpc) | 7/12, 7/10, 6/10 |
| link forced to HBR2 (540000; settled at 24 and 18 bits per pixel instead of 30) | 4/8, 5/8 |
| backlight 25 % | 6/10 |
| FBC disabled (`enable_fbc=0`) | 7/10 |
| NVIDIA dGPU kept awake (runtime PM off) | 5/10 |
| 60 Hz vs 165 Hz | both affected |

Earlier boots: `enable_psr=0`, `enable_panel_replay=0`, `enable_dc=0` had no effect. Panel has no PSR/Panel Replay support (`Sink support: PSR = no, Panel Replay = no`).

## DPCD / sink identification
```
0x000: 14 1e 44 41 00 00 01 c0 02 00 02 00 00 0b 80     (DPCD 1.4, max 8.1G, 4 lanes, enhanced framing)
0x700 (eDP): 04 9b 86 04 1e     sink rates: 162000 216000 243000 270000 324000 432000 540000 810000
0x400 (sink OUI / device id / HW/FW rev): 38 ec 11 00 00 00 00 00 00 00 00 00
DSC DPCD 0x060: 00 00 00 76 0b 01 01 80 00 01 06 66 08 00 00 00   (DSC sink support: no)
Intel HDR AUX backlight interface v1 detected, "SDR backlight is controlled through PWM"
```

## Related
- The proposed patch "drm/i915/display: Add quirk for interlane align bit on CH7511" addresses the same failure mode (`intel_dp_needs_link_retrain()` ORs in DP_INTERLANE_ALIGN_DONE) but is keyed to a CH7511 bridge (PCI 0x0f31, sink OUI 2b 02 f0) and does not match this machine (I could not verify its merge status).

## Result with a local workaround (suggests the sink misreports the bit)
Local patch (ignore DP_INTERLANE_ALIGN_DONE in `intel_dp_needs_link_retrain()` for eDP only; per-lane CR/EQ/symbol-lock bits still checked), built against the exact Ubuntu 7.0.0-42.42 sources:
- 3 consecutive boots: 1 link training, 0 retrains each (before: a boot with 12 trainings / 11 retrains).
- 12 consecutive 60 Hz <-> 165 Hz modesets: 0 retrains (before: 7/12, 7/10, 6/10).
- The picture is clean (no blanking, no corruption) with the bit ignored, which suggests the panel is not actually losing alignment and the TCON reports INTERLANE_ALIGN_DONE=0 during normal operation.
Patch:

```diff
@@ intel_dp_needs_link_retrain()
+	if (intel_dp_is_edp(intel_dp))
+		link_status[DP_LANE_ALIGN_STATUS_UPDATED - DP_LANE0_1_STATUS] |= DP_INTERLANE_ALIGN_DONE;
```

A proper fix would be a DPCD/panel quirk (like the CH7511 one) keyed on device 0xa7a0 / subsystem 1462:13c3 / sink OUI 38 ec 11.

## Question / request
Is the sink genuinely losing inter-lane alignment 2 s after enable, or does this TCON (sink OUI 38:ec:11) report INTERLANE_ALIGN_DONE=0 during normal operation? If the latter, could a DPCD quirk (device 0xa7a0, subsystem 1462:13c3, sink OUI 38 ec 11) ignore that bit, like the CH7511 quirk? Happy to test patches and provide further drm.debug logs / DPCD dumps (0x500 not read yet).
