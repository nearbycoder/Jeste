# Jeste: improvement plan (round 1)

Written 2026-10-06 on the `improvements` branch, against v0.1.0 (`8a38434`).
This is phase 1: what to improve and why. Nothing here is implemented yet.

## Baseline

| Check | Result |
|---|---|
| `python3 tests/run_tests.py --jobs 4` (lint, replay 133 cached routes, chapter proofs, end-to-end playthroughs, menu flow) | **PASS**, 14 s. All 9 chapters: end reachable, 75/75 collectibles proven, every golden run carried, UI flow passes. |
| Route robustness (from the suite) | Average 82%. Tightest main-path routes: `6-02→6-03` 33%, `7-09→end` 33%, `3-03→3-04` 38%, `1-05→1-06` 42%. |
| Screenshots via `tools/shot.tscn` (0-01, 0-02, 1-01, 6-01) | Render correctly. The art is strong, the title cards read well, and no visual bugs were seen. |
| Frame time (probe scene, `--disable-vsync`) | 7–13 ms/frame in 0-01, 4-01 and 7-01 while the machine was at load average 35–50, so these numbers are noisy. No evidence of a real performance problem on this hardware. Low-end hardware is untested. |
| Export | Only the Linux release template is present (`build/templates/`). No Windows, macOS or web templates are installed. The official 4.7.2 template bundle is reachable (1.28 GB). |
| Wine / Windows runtime | Not available on this machine, so a Windows build can be exported but not run here. Firefox is available, so a web build can be run here. |

### Probes run for this plan (throwaway, not committed)

1. **Advanced tech on the solver's routes.** I replayed all 133 cached routes and counted
   world events. The bot uses supers, hypers or wall-bounces on 63 of 133 routes, including
   most required paths from `1-01` onward. The game never teaches any of these (`grep` of
   `data/story/`), so the bot's routes aren't evidence of what a new player can do.
2. **No-tech solvability.** I temporarily patched the solver to prune any branch that
   fires `super`, `hyper` or `wallbounce`, then re-solved every affected task (30 required
   paths and 33 collectible or secret-room tasks). **All 63 solved.** The game is
   beatable, with 100%, without untaught techniques, but the suite doesn't currently prove or
   report that. Robustness scores are computed on the bot's tech-heavy routes, so they
   are a poor proxy for human difficulty.
3. **Analog stick in menus.** I fed one realistic stick push (axis values 0.3 → 1.0)
   into the title menu. **The cursor moved 3 rows (Climb → Quit) instead of 1.**
   `InputEvent.is_action_pressed()` returns true for every joypad-motion event past the
   deadzone, and every menu (`title.gd`, `hud.gd`, `chapter_select.gd`, dialogue) reacts
   to raw events. On a real pad, stick navigation is close to unusable and volume
   sliders jump several steps. The D-pad is fine. This was never caught because gamepads were only
   tested with simulated button input.
4. **Continue corrupts best times (code read).** `Level._ready` starts `chapter_time` and
   `deaths_this_chapter` at 0 even when started from `Continue` / resume
   (`Game.start_chapter(n, room)`). `_on_end` then stores that partial time as the
   chapter's **Best** time, which chapter select displays. For example, resume in the last room,
   finish in 10 s, and Best shows `0:10.xx`. The results screen also under-reports deaths and
   time.

## Ranked improvements

Impact is for a real player. Effort: S (≤ half a day), M (about a day), L (several days).

| # | Improvement | Impact | Effort | Risk | Grounding |
|---|---|---|---|---|---|
| 1 | **Gamepad fixes:** edge-triggered stick navigation in every menu, device-aware button labels (Xbox / PlayStation / Nintendo naming from `Input.get_joy_name`), pad prompts that match the real bindings | High | S–M | Low | Probe 3. `PAD_LABELS` is hard-coded Xbox ("X", "RB"). Precision platformers are mostly played on pads. |
| 2 | **Windows and web builds:** presets, a scripted export (`tools/export.py`), a web smoke test in a browser, README and release-notes updates | High | M | Medium | Linux-only is the first known issue, and the blog says other builds "aren't published yet". The web build is the biggest reach gain (play in a browser, no install). Risks: the web build is single-threaded, so `RoomView.prebake` (`WorkerThreadPool`) may stall at chapter start, and GDScript terrain baking is slower in wasm. Windows runtime can't be tested here. |
| 3 | **Continue / best-time bug:** carry chapter time and deaths through resume, and only record Best for runs started at the chapter start | Medium | S | Low | Probe 4. Silently corrupts the one stat speedrunners look at. |
| 4 | **Human-difficulty pass:** add a *no-advanced-tech* proof to the suite, report robustness on no-tech routes, then loosen the tightest main-path rooms | High | M | Medium | Probes 1–2. The "tuned against a bot" known issue is currently measured with a tech-heavy bot. Geometry edits invalidate cached solutions (re-solved by the suite) and make the trailer slightly stale. |
| 5 | **Display options:** window scale picker (2×…max), a first-launch window sized to the monitor, fullscreen also in the pause menu | Medium | S–M | Low | Known issue "no resolution picker". On this 4K monitor the fixed 1280×720 window is a ninth of the screen, and fullscreen is only reachable from the title. |
| 6 | **Reduce-flashing / effects toggle:** gate `hud.flash`, the death flash, the post-FX chromatic shimmer and screen shake behind one accessibility option | Medium | S | Low | Bells, deaths and dashes all flash full-screen (`level.gd`, `post_fx.gd`). There is no photosensitivity option. |
| 7 | **Frame pacing on high-refresh displays:** interpolate rendered player and camera positions between 60 Hz sim ticks | Medium | M | Medium | The sim runs at 60 Hz with no interpolation (`player_view` / `camera` move only on ticks), so 120/144 Hz monitors will show judder. Unverified here: this monitor's refresh rate and judder weren't measured. |
| 8 | **Cutscene skip** (hold to skip a whole scene) | Low–Med | S | Low | First-time cutscenes are 6–15 lines and can only be advanced line by line. Seen scenes already auto-skip. |
| 9 | **Gamepad rebinding** | Low–Med | M | Low | Keyboard is fully rebindable, pads are fixed. Less urgent once #1 lands. |
| 10 | **Choose a license** | Medium (for distribution) | S | — | Owner decision only. README: "No license has been chosen yet." |
| 11 | **macOS build** | Medium | M | High | Needs signing and notarization to avoid Gatekeeper blocks, and can't be tested here. Defer. |
| 12 | **Content: remixed "B-side" rooms or a post-game challenge set** | Medium | L | Medium | The full clear is short (the bot needs under 4 minutes). Out of scope until the basics above are solid. |

Considered and not ranked: a performance pass (no measured problem; revisit if the web
build is slow) and audio (all music and sfx are generated and were not judged by ear in
this pass).

## Proposed scope for round 2

Items 1–6, in this order (smallest and safest first; item 2 depends on an owner decision).

### A. Gamepad menu fix and device-aware prompts (#1)
- **Do:** add one shared `Game.menu_pressed(ev, action)` helper. It treats joypad motion as a
  press only when the axis crosses the threshold from below (per device and axis), with
  hold-to-repeat after ~0.35 s. Use it in title, options, controls, chapter select, pause,
  assist, results, dialogue and credits. Label pad buttons by family from `Input.get_joy_name`
  (Xbox: A/X/RB, PlayStation: Cross/Square/R1, Nintendo: B/Y/R).
- **Accept:** one stick push moves any menu exactly one row or one slider step. Holding
  repeats at a steady rate. D-pad and keyboard behave as before. Prompts read correctly for
  each pad family.
- **Verify:** extend `tests/ui_flow.gd` with the probe-3 sequence on the title menu,
  options sliders and the pause menu (expect +1). Add a unit check for label mapping from sample
  joy names. Run the full suite. Honest caveat: still no physical controller on this machine.

### B. Resume keeps chapter time, deaths and best time honest (#3)
- **Do:** store `time` and `deaths` in `Game.data.resume` on room entry and restore them on
  Continue. Mark resumed runs and never let a run that didn't start at the chapter
  start set Best.
- **Accept:** after resuming, the results screen shows the cumulative time and deaths, and
  Best only changes on a full run.
- **Verify:** new ui_flow step: start chapter 1, advance rooms, return to map,
  continue, finish via replay. Assert the saved `best_time` didn't drop below the full-run time.

### C. Windows and web builds (#2), needs owner decision (see below)
- **Do:** add "Windows Desktop" (x86_64, embedded PCK) and "Web" (no-threads) presets.
  Add `tools/export.py` to export Linux, Windows and web, zip each with a SHA-256, and
  print sizes. Make the web build behave (no Quit, which is already handled; fullscreen
  via user gesture; check save persistence). If the chapter-start bake stalls, spread
  `prebake` across frames when threads are unavailable. Update the README, badges and Play-it
  section only for what is verified.
- **Accept:** all three exports succeed headless. The web build loads in Firefox, reaches
  the title, starts the prologue, saves, and survives a reload with progress intact. The chapter-start
  stall stays under about 2 s.
- **Verify:** run the export script, serve the web build locally, and drive it with the
  browser preview tools (screenshots of title and in-game). The Windows build is checked as a valid
  PE with its PCK embedded but **not run**. The README will say "Windows build untested" until
  someone runs it.

### D. Human-difficulty pass (#4)
- **Do:** add a `forbid_tech` option to `Solver` (prune `super`, `hyper` and `wallbounce`). The
  suite solves and caches a no-tech route per task (`tests/solutions_basic/`), reports
  "beatable without advanced techniques" per chapter, and computes robustness on the
  no-tech routes. Then widen platforms or gaps in at most 3 main-path rooms whose no-tech
  robustness is lowest, preferring Chapters 1–3 where new players are.
- **Accept:** the suite proves every chapter end and every collectible without
  advanced tech. Main-path no-tech robustness for the tuned rooms rises (target ≥ 60%).
  All existing proofs still pass.
- **Verify:** full suite plus `--resolve` on edited chapters, before/after robustness
  table in `tests/REPORT.md`, and `tools/strip.tscn` captures of each edited room for review.
  README: change "difficulty tuned against a bot" only as far as the evidence supports.

### E. Display options (#5)
- **Do:** add a Window Size option (2× up to the largest integer scale that fits the screen),
  pick a first-launch default of about 75% of the screen, and add Fullscreen to the pause Options.
- **Accept:** the size persists across launches, toggling fullscreen and back restores the chosen
  size, and integer scaling stays pixel-perfect.
- **Verify:** ui_flow covers the new options (headless settings round-trip), plus windowed
  screenshots at two scales on this display.

### F. Reduce flashing (#6), if time allows
- **Do:** add one "Flashing Effects: Full / Reduced" option that scales `hud.flash`, the death
  flash and the post-FX shimmer to ≤ 20% and caps shake.
- **Accept and verify:** ui_flow toggles it, and a `shot.tscn` capture at a bell pickup
  compares frame brightness with Full vs Reduced.

## Decisions needed from the owner

1. **Export templates for item C.** Windows and web need the official Godot 4.7.2 export
   templates (1.28 GB download). Options: (a) install them in Godot's standard location
   `~/.local/share/godot/export_templates/4.7.2.stable/`, which is outside this repo but could
   be shared with other Godot sessions; or (b) extract only the needed templates into the
   git-ignored `build/templates/` and point the export script at them. I'll default to (b),
   which stays inside the repo, unless told otherwise.
2. **Publishing.** This round only builds and verifies artifacts locally. Releasing them,
   hosting the web build (GitHub Pages, itch.io or nearbycoder.com) and updating the blog
   post are up to the owner.
3. **Level geometry changes (item D)** will make the trailer's footage of edited rooms slightly
   out of date. The plan is to keep the trailer as is (it is a v0.1.0 trailer) unless the
   owner wants it re-recorded later.
4. **License** (#10) is still unchosen and blocks any third-party distribution such as itch.io.
