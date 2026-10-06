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

## Round 1 scope

Items 1–6, in this order (smallest and safest first; item 2 depends on an owner decision).
(Planned in phase 1 as "round 2"; implemented and merged as round 1.)

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

## Round 1 results (2026-10-06)

All commits are on `improvements`; nothing has been pushed. The full suite passes after every
item: fastest-route and basic-moveset proofs for all 9 chapters, golden runs, end-to-end
playthroughs and the menu flow. Screenshots are in `docs/media/improvements/`.

| Item | Status | Commit(s) | Verified by |
|---|---|---|---|
| B. Continue keeps time, deaths and Best honest | Done | `6361f7c` | ui_flow resumes with seeded time and deaths, finishes, and asserts Best is untouched (fails without the fix). e2e asserts full runs record Best. |
| A. Stick menus and pad button names | Done | `83a726d`, `83c7681` | ui_flow drives realistic stick pushes through the title, options slider and pause menu, expecting exactly one step each (fails without the fix), and checks a held stick still reads as held for gameplay. Family mapping is checked on sample device names. **Simulated input only; no physical pad.** |
| E. Window Size, auto size, fullscreen in pause | Done | `5f87837` | ui_flow covers the option and the scale maths for 6 screen sizes. Real window checked under Wayland on a 4K display: Auto 9×, then 3×, fullscreen and back restores 3×. Under X11 (XWayland) here, windows launched from scripts started minimised even with plain Godot calls, so X11 was not checked by eye. Screenshots: `title_options_window_size.png`, `pause_options_display.png`. |
| F. Reduce Flashing | Done | `cc4c914` | ui_flow toggles it. On 1-02, a bell-strength flash lifts mean frame luminance by 0.49 at full strength and by 0.09 when reduced (baseline 0.14). Screenshot: `flash_full_vs_reduced.png`. |
| D. Human-difficulty pass | Done | `1a9749e`, `be7023c` | See below. |
| C. Windows, web, macOS | **Presets only** | `9d590d2` | Godot parses all three presets, and export stops only on the missing 4.7.2 templates (outside the repo, not installed, per the orchestrator). No build was produced or run. The README says so. |

### Item D details and deviations from the plan
- The suite now solves a second, basic-moveset route per task (`tests/solutions_basic/`).
  All 9 chapters and all 75 collectibles are proven without supers, hypers or wall-bounces.
- **Metric change.** The planned tuning signal, robustness on basic routes, turned out
  to mostly measure open-loop replay drift. In 0-06 (25%), none of the failing slips were
  deaths; Mira just didn't reach the flag without steering. The suite now reports
  **lethality** (the share of 1-frame slips, inserted or dropped, that kill), and
  `tools/slip_deaths.gd` maps where they die.
- **Rooms tuned by lethality, not chapter.** The plan preferred Chapters 1–3. The data put
  the worst rooms elsewhere, so I tuned the three most lethal main-path rooms where one
  fix addressed a clear hotspot, keeping each room's idea:
  - 7-05: ledge extended 3 tiles, 73% → 29%.
  - 6-06: chase delay 45 → 60 frames, 40% → 31%.
  - 2-03: floor where Mira leaves the lower curtain, 35% → 4%.

  Before/after shots: `room_2-03_before_after.png`, `room_7-05_before_after.png`.
- Still the most lethal: 7-04 (35%), 4-05 s1 (35%) and 7-03 (33%). They are candidates for a
  later pass, ideally after a human playtest.

### Deviations in A
- No hold-to-repeat for the stick. Keyboard and D-pad don't repeat in these menus either, so
  one push equals one step everywhere.

### Still open (owner decisions)
- Export templates, plus running and checking the Windows, web and macOS builds. The Linux
  template in the git-ignored `build/templates/` is not in Godot's standard path either, so a
  fresh Linux export also needs templates installed.
- Publishing or hosting any build, license choice, signing and notarization.
- Physical-controller testing, and a human playtest of the tuned rooms.

## Round 2 scope (2026-10-06)

Picked from the ranked list and from what round 1 turned up. Everything here can be verified
on this machine with the existing suite, ui_flow and screenshots.

Not picked:
- **#7 frame pacing:** this monitor runs at 119.98 Hz, an exact multiple of the 60 Hz sim, so
  the uneven judder of 144/165 Hz displays can't be observed or verified here.
- **#2 / #11 builds:** these still need export templates (an owner decision).
- **#12 content:** too large for this pass.

### A. Hold-to-repeat in menus
- **Do:** holding a direction (keyboard, D-pad or stick) repeats menu moves after 0.35 s, then
  every 0.09 s. This covers the title, options, controls, chapter select, pause, assist and
  results screens. Gameplay input is untouched.
- **Accept:** a tap still moves exactly one step. Holding for about 1 s moves several steps at
  a steady rate. Releasing stops repeats immediately. Holding a non-direction action never
  repeats.
- **Verify:** ui_flow holds a D-pad button, a key and the stick for a fixed number of frames
  and checks the step counts. The existing single-push stick checks must still pass.

### B. Skip a whole cutscene
- **Do:** hold Pause during a cutscene (Esc / Enter / P, or Start) to fill a small
  "Hold to skip" ring. A full ring skips to the end of the scene and still runs its
  commands, so NPC visibility, music and seen-flags end up exactly as if it had been read.
  Tapping keeps advancing line by line.
- **Accept:** about 0.6 s of holding skips the rest of the scene. The end state (mode,
  seen-flags, NPC visibility) matches reading it through. End-of-chapter scenes still lead
  to the results screen.
- **Verify:** ui_flow holds pause during the prologue's opening scene and checks that the
  level is back in play mode with `pro_arrive` marked seen. A screenshot shows the skip ring.

### C. Route Ghost (opt-in assist hint)
- **Do:** add Pause → Assist → **Route Ghost**. When on, a translucent Mira replays the
  suite's proven basic-moveset route for the current room from the spawn she used, looping,
  and restarting with her on each respawn. Routes ship in `data/hints.json`, generated from
  `tests/solutions_basic/` by the suite. The ghost is purely visual: it uses its own
  simulation, collects nothing and makes no sound. After 10 deaths in one room, the HUD
  shows a one-line nudge pointing to it (shown once per room).
- **Accept:** every room and spawn on a chapter's main path has a hint, and replaying it in a
  fresh World clears the room. Toggling the ghost on shows it moving along the route, off
  hides it. The player's save, berries and deaths are unaffected.
- **Verify:** the suite checks hint coverage and that each hint replays to its exit. ui_flow
  toggles the assist and checks the ghost is visible and advancing. Screenshots of the ghost in
  two rooms.

### D. Gentle pass on the next most lethal rooms
- **Do:** use `tools/slip_deaths.gd` on 7-04, 4-05 (spawn 1) and 7-03, and apply a small
  geometry or parameter change where one hotspot dominates. Keep each room's idea.
- **Accept:** lethality of each tuned room drops on the same route. Every proof stays green:
  fastest and basic moveset, collectibles, golden runs, e2e and menu flow. Rooms without a
  clear single hotspot are left alone and reported.
- **Verify:** before/after slip-death numbers, the full suite, and before/after screenshots.

### E. Gamepad rebinding (stretch, only if A–D land cleanly)
- **Do:** in Options → Controls, the Jump, Dash and Grab rows accept a pad button as well as a
  key, swapping on conflicts. Prompts show the bound button.
- **Accept and verify:** ui_flow rebinds Jump to a pad button with a simulated press, then
  checks the InputMap and the prompt label, and that Reset Defaults restores the pad defaults.

## Round 2 results (2026-10-06)

All commits are on `improvements-2`; nothing has been pushed. The full suite passes after every
item: fastest-route and basic-moveset proofs for all 9 chapters, golden runs, end-to-end
playthroughs, the menu flow and the new hint replay check. Screenshots are in
`docs/media/improvements/round2/`.

| Item | Status | Commit | Verified by |
|---|---|---|---|
| A. Hold-to-repeat in menus | Done | `8c50afc` | ui_flow holds a D-pad button, a key and the stick for 40 frames (4–6 steps each) and checks a tap is exactly one step. It fails with repeat disabled (one step). The round-1 single-push stick checks still pass. |
| B. Hold Pause to skip a cutscene | Done | `a660d55` | ui_flow holds Esc in the first cutscene, checks it is still running at 10 frames and back in play, unpaused, at 50. Skipping runs the same path as fast mode, which the end-to-end playthroughs exercise in every chapter. Screenshot: `cutscene_hold_to_skip.png`. |
| C. Route Ghost assist | Done | `26150dc` | The suite writes `data/hints.json` (71 entries, every reachable room/spawn) and fails on a gap. `tests/hints_check.gd` replays every shipped hint to its exit with no advanced tech, and flags a deliberately corrupted entry. ui_flow turns it on, checks the ghost is visible and advancing in its own World, then turns it off. The exported Linux PCK stores `res://data/hints.json`. Screenshots: `route_ghost_2-03.png`, `route_ghost_7-05.png`. |
| D. Next most lethal rooms | **No change** | none | See below. |
| E. Pad rebinding (stretch) | Done | `0fb7ebe` | ui_flow binds Jump to X with a simulated button press, checks the D-pad is refused, A swapped to Dash and the label reads X, and that Reset Defaults restores A/Y and X/B. Screenshot: `controls_pad_rebinding.png`. **Simulated input only.** |

### D: why no rooms changed
`tools/slip_deaths.gd` on the basic-moveset routes:
- **7-04 (33% of slips fatal):** deaths cluster below the comedy block that vanishes when Mira
  dashes. That swap is the room's mechanic. A safe floor there would let a player wall-climb
  the right side to the exit and skip the puzzle.
- **4-05 from the secret room (35%):** deaths are on the spike strip atop the exit block, where
  tailwind jumps land. Turning 2 spikes into floor left it at 35%, and turning 3 into floor
  only got it to 24%. Each removal just moved the deaths one tile along as slipped landings
  slid further in the wind, so it's the hazard working as designed, not a fixable hotspot.
  The main-path route through 4-05 (from the left) is already 0% lethal. Reverted.
- **7-03 (29%):** deaths are on the lower-left wall spikes. Removing them would open a climb
  straight up to the exit ledge, bypassing the curtains.

These rooms are left as designed. Route Ghost (C) now gives players who get stuck there a
proven way through. A human playtest is still the right next signal.

### Still open
- **Frame pacing on 144/165 Hz displays (#7):** this monitor is 120 Hz, which divides evenly by
  the 60 Hz sim, so judder can't be observed here.
- **Route Ghost in rooms with moving parts:** the ghost's own gondolas, crumbling boards and
  chaser aren't drawn, so it can look like it rides thin air. Drawing a second set of
  moving objects is possible but was out of scope.
- **Owner decisions (unchanged):** export templates and Windows/web/macOS builds, signing and
  notarization, hosting, license, releases and tags, physical-controller testing.

## Round 3 scope (2026-10-06)

Picked from the two items round 2 left open and from gaps in the Route Ghost, which is now the
game's main answer to "this room is too hard". Everything here can be checked on this machine.
All tests and probes run with Godot's user data redirected into the git-ignored `build/`, and
the real save's checksum is compared before and after.

Not picked:
- **Windows / web / macOS builds, license, publishing:** still owner decisions.
- **Checkpoint select** (start a chapter from any room you've reached, to go back for a missed
  berry): useful, but it touches chapter select, resume and Best-time rules. Kept on the list.
- **Content (#12):** too large for this pass.

### A. Smooth Motion (frame interpolation)
- **Why:** the simulation steps at a fixed 60 Hz and everything is drawn at the last step's
  position. On 144 or 165 Hz displays steps land on frames unevenly (judder). The same happens
  on *every* display at the Game Speed assist: at 50% the sim steps 30 times a second, so Mira
  and the camera move at 30 fps even on a 120 Hz screen. That one can be seen here.
- **Do:** keep the previous step's positions and draw Mira, the camera, gondolas, the Grin and
  the Route Ghost between the last two steps. Add **Options → Smooth Motion: Auto / On / Off**
  (title and pause). Auto turns it on only when the refresh rate isn't a multiple of 60 Hz or
  Game Speed is below 100%, so the common 60/120 Hz case at full speed keeps today's zero added
  latency. The simulation itself doesn't change, so routes, proofs and replays are unaffected.
- **Accept:** with it on, per-frame screen movement during a steady run or dash is even
  (no 0-px / 2-px alternation) at 144 fps and at 50% speed. With it off, rendering is unchanged.
  Respawns, room transitions and freeze frames don't smear.
- **Verify:** a probe scene replays a proven route at a forced frame rate (144 fps at 100%, 60 fps
  at 50%) and logs Mira's drawn position and the camera each frame, Off vs On, reporting the
  spread of per-frame steps. ui_flow cycles the option and checks the Auto rule. Full suite.

### B. Route Ghost shows its own moving parts
- **Why:** the ghost runs in its own simulation, so in rooms with gondolas, crumbling boards,
  gates, cracked walls, mask blocks or a chaser, she reacts to things that aren't drawn. She
  "rides" nothing, stands on boards the player already broke, or walks through mask blocks.
- **Do:** draw, in the ghost's tint, the ghost world's gondolas, plus any crumbling boards,
  gates, cracked walls and mask blocks that are solid for her but not for the player. In chase
  rooms, draw her own Grin, also tinted.
- **Accept:** in a gondola room the ghost's gondola carries her. In a crumble room after the
  player breaks the boards, the ghost's intact boards are drawn under her. In a chase room a
  tinted Grin follows her. Nothing changes when the ghost is off.
- **Verify:** a scripted capture of the ghost mid-route in a gondola room (4-xx), a crumble room
  (1-xx) and a chase room (2-xx), plus ui_flow checks that the ghost layer only draws while
  the ghost is on. Full suite.

### C. Route Ghost button display
- **Why:** the ghost shows *where* to go but not *what to press*. A dash direction or a
  held grab is hard to read from a translucent sprite.
- **Do:** while the ghost is on, a small HUD strip shows the buttons the ghost is holding this
  frame (direction arrows, Jump, Dash, Grab), labelled with the player's own bindings
  (keyboard or pad, following the last device used). It can be turned off with the ghost.
- **Accept:** the strip matches the ghost's inputs frame by frame and hides with the ghost.
- **Verify:** ui_flow compares the strip's state with the ghost's input stream for a few hundred
  frames. Screenshot of the strip during a dash.

### D. Grab Mode: Hold / Toggle
- **Why:** climbing means holding a shoulder button or key for long stretches. A toggle is a
  common accessibility option in this genre and costs nothing to players who don't use it.
- **Do:** **Options → Controls → Grab Mode**: Hold (default) or Toggle (press once to grab,
  again to let go; the latch also clears on death and room change).
- **Accept:** in Toggle mode one press then release gives a held grab to the simulation until
  the next press. Hold mode is unchanged.
- **Verify:** ui_flow drives a press/release sequence through `Game.read_input()` in both modes,
  and checks the setting persists and survives Reset Defaults as documented. Full suite.

## Round 3 results (2026-10-06)

All commits are on `improvements-3`; nothing has been pushed. The full suite passes after every
item: fastest-route and basic-moveset proofs for all 9 chapters, golden runs, end-to-end
playthroughs, hint replays and the menu flow. Every run used a throwaway user-data directory
under `build/`. The real save's checksum was the same before and after. Screenshots and the
chart are in `docs/media/improvements/round3/`.

| Item | Status | Commit | Verified by |
|---|---|---|---|
| A. Game Speed fix + Smooth Motion | Done | `5adab0c` | See below. |
| B. Ghost's moving parts | Done | `21ae5c5` | ui_flow: in 1-03, only boards are drawn for the ghost, and only after the player breaks them; in 4-02 her gondola leaves the player's idle one; her Grin hides with her. Screenshots of a gondola, a chase, crumbling boards and mask blocks: `route_ghost_moving_parts.png`. Affects 28 of the 69 hinted rooms. |
| C. Ghost button strip | Done | `45e463f` | ui_flow follows the strip for 150 frames against the ghost's input stream (held buttons fully lit, buttons released over 30 frames ago dark). Screenshot during a dash: `route_ghost_buttons.png`. |
| D. Grab Mode: Hold / Toggle | Done | `81e3612` | ui_flow toggles it on the Controls screen and drives press/release sequences through `Game.read_input()` in both modes. It checks that a death releases the latch and that Reset Defaults keeps the mode. Screenshot: `controls_grab_mode.png`. |

### A: what was found, and the numbers
- **Game Speed never slowed gameplay.** The probe showed that in Godot 4, `Engine.time_scale`
  shrinks the physics delta but not the number of physics ticks. The level stepped its
  fixed-step simulation once per tick, so at "50%" Mira still moved at full speed; only
  animations and timers slowed. This has been true since v0.1.0. The level now steps when a
  whole step is owed (every other tick at 50%) and carries jump/dash taps that land between
  steps. Measured on 1-01's route: 0.45 steps per tick at 50% vs 0.90 at 100% (dash freeze
  frames make up the rest). ui_flow counts 20 steps in 40 ticks at 50% and 40 at 100%; that
  check fails with the old loop.
- **Smooth Motion** (Options, Auto/On/Off) draws between the last two steps. The scope's
  premise that judder at 50% speed "can be seen here" turned out to be wrong: before the
  fix, 50% didn't change the step rate at all. With the fix, 50% does run at 30 steps a
  second, which is what Smooth Motion now smooths. `tools/motion_probe.tscn` replays a route
  at a forced frame rate. Per-frame movement of Mira's drawn position during steady
  horizontal runs in 0-02 (spread = standard deviation of per-frame steps):

  | Case | Off: spread, frames that don't move, pixel steps | On |
  |---|---|---|
  | 144 fps, 100% speed | 0.70 px, 74%, 0–2 px | 0.19 px, 30%, 0–1 px |
  | 60 fps, 50% speed | 0.76 px, 68%, 0–2 px | 0.25 px, 29%, 0–1 px |
  | 60 fps, 100% speed | 0.50 px, 0%, 1–2 px | unchanged (Auto keeps it off) |

  On 1-01's dash-heavy route at 144 fps the spread goes from 1.42 to 0.59 px and the largest
  per-frame jump from 4 to 2 px. Chart: `smooth_motion_trace.svg`. Not verified: watching it
  on a real 144/165 Hz display (this one is 120 Hz, where Auto stays off).
- Cached route files show changes only because `world.gd` is part of their hash. The routes are
  unchanged and were re-verified.

### Deviations and limits
- Grab Mode's latch is **not** cleared on room change (the scope said it would be). Clearing it
  would drop a player who climbs up into the next room. It clears on death and at chapter start.
  While it's latched, a small "Grab on" prompt shows bottom right.
- The ghost's parts are drawn only where they're solid for her and not for the player. A block
  that is solid for the player but not for her is still drawn, so she can appear to pass
  through it (seen in 3-02 when her mask blocks have swapped and the player's haven't).
- ui_flow now resets settings to defaults at start. A `route_ghost: true` settings file had
  made it fail, which also means a developer's own settings could break the test.

### Still open
- Checkpoint select (start a chapter from any room reached), still unranked against content.
- A human playtest at 50% speed now that it really slows the game, and a look at Smooth Motion
  on a real 144/165 Hz display.
- **Owner decisions (unchanged):** export templates and Windows/web/macOS builds, signing and
  notarization, hosting, license, releases and tags, physical-controller testing. One new
  point: v0.1.0's Game Speed assist doesn't slow gameplay, and the fix reaches players only
  in a new release.
