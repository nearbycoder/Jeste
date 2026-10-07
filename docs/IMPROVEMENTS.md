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

## Round 4 scope (2026-10-06)

Baseline on `improvements-4` (from `main` = `origin/main` = `2a288a5`): the full suite passes
in 32 s at load average 8. All runs this round use a throwaway user-data and temp directory
under the git-ignored `build/r4/`, and the real save's checksum is compared before and after.

Picked for a real player's experience, and because each can be checked here without a
display-only judgement call:

### A. Saves survive a crash or a bad write
- **Why:** `Game.save()` opens the save with `FileAccess.WRITE`, which empties the file
  before writing it, and it runs on every room entry and every berry. A crash, power cut or
  full disk at that moment leaves an empty or half-written file. On the next launch
  `load_save()` can't parse it, silently starts a fresh save, and the first room entry
  overwrites the damaged file. The whole climb is lost without a word. Settings work the same way.
- **Do:** write to a temporary file, check it, keep the previous good file as a backup, then
  rename into place. On load, fall back to the backup if the main file is missing, empty or
  unparseable, keep the unreadable file aside (`.corrupt`) instead of overwriting it, and say
  so once on the title screen.
- **Accept:** a truncated, empty or garbage save loads the last good backup. A damaged file is
  never overwritten. A normal save round-trips unchanged. Settings behave the same.
- **Verify:** a new headless check (`tests/save_check.gd`, in the suite) that writes saves into
  the sandboxed `user://`, damages them in each way, reloads and compares. Fails on the old code.

### B. Checkpoint select
- **Why:** to go back for a missed berry or bell in room 9 of a chapter, a player must replay
  the whole chapter, or rely on *Continue*, which only remembers the last room entered. With 61
  berries and 7 bells, collecting is most of the replay value, and the genre standard is to let
  you start from any checkpoint you've reached.
- **Do:** remember every room entered. On chapter select, choosing a chapter with more than one
  reached checkpoint opens a picker: Left/Right steps through the main-path rooms reached
  (secret rooms are never listed), the postcard shows the chosen room live, and the text column
  shows which berries and the bell of that room you still lack. *Continue* stays the default
  when there is one and keeps its time and deaths. Any other room starts a fresh, non-Best run
  (Best still needs a start-to-end run, as today). Old saves are backfilled: a completed chapter
  has all its checkpoints, otherwise rooms up to the *Continue* room and rooms where something
  was collected.
- **Accept:** each listed room starts the level in that room at a spawn with a proven route to
  its exit. Unreached rooms and secret rooms are never offered. Collectible markers match the save.
  Starting from the chapter start still records Best; starting elsewhere never does.
- **Verify:** ui_flow opens the picker on a seeded save, steps to a room, confirms, and checks
  the level's room, `full_run` and time; a unit check of the reached/backfill rules; the suite
  checks every main-path room's spawn 0 has a shipped Route Ghost hint (a proven route);
  screenshot.

### C. Pause → Restart Chapter
- **Why:** golden-berry attempts and speedruns restart a chapter many times. Today that takes
  Return to Map, Climb, then *Restart chapter* in the resume prompt, with two screen wipes.
- **Do:** a *Restart Chapter* row in the pause menu with a Yes/No confirm (a misclick shouldn't
  throw away a long climb). It starts a fresh full run at the chapter start, so Best and the
  golden berry are both possible. The pause screen also shows this chapter's berries.
- **Accept:** confirming starts the chapter at its first room with time and deaths at 0 and
  `full_run` true; No or Back returns to the pause menu unchanged.
- **Verify:** ui_flow walks pause → Restart Chapter → No, then → Yes, and checks the new level.
  Screenshot of the confirm.

Not picked: the Route Ghost block-drawing limit (small visual gap, and a fix means hiding the
player's own blocks); physical controllers and 144/165 Hz displays (no hardware here); builds,
license and releases (owner decisions); new content (too large).

## Round 4 results (2026-10-06)

All commits are on `improvements-4`; nothing has been pushed. The full suite passes after
every item: fastest-route and basic-moveset proofs for all 9 chapters, golden runs, end-to-end
playthroughs, hint replays, the new save check and the menu flow. Every run used a throwaway
user-data directory under `build/`. The real save's checksum was the same before and after. Screenshots are in
`docs/media/improvements/round4/`.

| Item | Status | Commit | Verified by |
|---|---|---|---|
| A. Saves survive a crash or a bad write | Done | `4794b5a` | `tests/save_check.gd` (41 checks, now in the suite): truncated, empty, garbage and non-object saves load the backup and are kept as `.corrupt`; a later write leaves `.corrupt` alone; a crash between the two renames loads the backup quietly; both files damaged gives a fresh start without deleting anything; the real `load_save()` recovers from a torn write; Erase Save leaves no backup. Screenshot: `title_save_restored.png`. |
| Found on the way: rebinding left Dash stuck | Fixed | `9d4f512` | See below. |
| B. Checkpoint select | Done | `b95aa48` | ui_flow seeds a save, opens the picker on chapter 1, checks the list (1-01…1-04, no secret room), clamping and Back, starts from 1-03 (room, practice run, zero time and deaths), then Continue from the secret 1-05s (time and deaths carried). A unit check covers the backfill rules, and every main-path room's spawn 0 has a shipped, proven Route Ghost route. Screenshots: `checkpoint_select.png`, `checkpoint_continue.png`. |
| C. Pause → Restart Chapter | Done | `1c1a4d5` | ui_flow from the 1-03 checkpoint run: opens the confirm (default Keep climbing), keeps climbing, then restarts and checks 1-01, a full run, zero time and deaths, unpaused. Screenshot: `pause_restart_chapter.png`. |

### The stuck Dash
The checkpoint steps in ui_flow started 1-03 and Mira immediately dashed into the spikes. Dash had
been "held" since an earlier step bound Jump to the pad's X, which was Dash: X was pressed while
it meant Dash and released after it meant Jump, so Dash never saw its release. In the game that
means the next level starts with a dash and the next press of Dash does nothing. The keyboard
does the same (hold X, bind Jump to X, let go), which a throwaway scene confirmed with and without
the fix. Keyboard rebinding shipped in v0.1.0, so the release has this bug. `setup_input()` now
starts every action released. ui_flow checks Dash right after the pad rebind and fails without
the fix.

### Deviations and limits
- **Save safety** protects against a crash or a failed write. It was checked by damaging files the
  way a torn write would, not by cutting power. Files are closed but not synced to disk, so after a
  power cut the newest save may be lost; the previous copy is still kept. The rename steps
  haven't been run on Windows or the web, where builds don't exist yet.
- **Checkpoints start at the room's first spawn**, as *Continue* always has, not at the side you
  entered from. Each one is proven to have a route to its exit. In a room whose spawn is at the
  screen edge (for example the secret dressing room) the postcard can't show Mira.
- **Restart Chapter** sits above Return to Map rather than near the top, so the existing menu
  order (and every pause step in ui_flow) stays the same.
- **Test sandbox:** `run_tests.py` now gives every Godot run its own `user://` in
  `build/test_user/`. The scope didn't ask for this, but nothing in the suite can reach a
  player's save now.
- **One flaky run.** One of four full-suite runs failed at an early menu step (Window Size)
  at load average 22, a part of the flow this round doesn't touch. ui_flow then passed 3 of 3
  standalone runs at load 20–30, and every other full-suite run passed. The cause wasn't found.
- Screenshots of the picker and the pause confirm were driven by throwaway scripts that call the
  menu's methods directly (kept in the git-ignored `build/r4/`). Scripted presses after the first
  didn't register in a windowed `tools/scene_shot.tscn` run. ui_flow drives the same screens
  with real input events, headless.

### Still open
- A human playtest, physical controllers and a real 144/165 Hz display (unchanged).
- Route Ghost: blocks solid for the player but not for her are still drawn (round 3 limit).
- **Owner decisions (unchanged):** export templates and Windows/web/macOS builds, signing and
  notarization, hosting, license, releases and tags, re-cutting the trailer. The v0.1.0 release
  still has three bugs that `main` fixes: Game Speed, saves lost to a crash, and the stuck Dash
  after rebinding.

## Round 5 scope (2026-10-06)

Baseline on `improvements-5` (from `main` = `origin/main` = `7dfdc52`): ui_flow passes standalone
in 6 s at load average 5. All runs this round use a throwaway user-data and temp directory
under the git-ignored `build/r5/`, and the real save's checksum is compared before and after.

**The round 4 flake, first.** Round 4's log shows the failure was `check window_auto failed
(opt_sel 3)`: the cursor was on Window Size but the setting wasn't Auto. ui_flow runs at
`--fixed-fps 60` and reads no wall-clock time, so load alone shouldn't change it. 30 standalone
runs, three at a time (load up to 14), all passed. Rather than guess at a fix, ui_flow will log
the last menu inputs and the relevant state when a check fails, so the next failure says why.

Picked for a real player's experience, and because each can be checked here:

### A. A controller that disconnects pauses the game
- **Why:** a pad whose battery dies or whose cable is pulled mid-climb leaves Mira running
  without input until the player notices. Pausing on disconnect is standard on consoles and
  Steam. Also, the rebind screen says "Esc Cancel" even when the player is on a pad, where
  Start cancels.
- **Do:** pause (with the pause menu) when any connected pad disconnects during play; if it was
  the pad driving prompts, prompts go back to the keyboard. The rebind hint names Start on a pad.
- **Accept:** a disconnect during play opens the pause menu; during the results screen, a
  cutscene's own pause or an open menu nothing breaks; a connect does nothing.
- **Verify:** ui_flow emits `Input.joy_connection_changed` (disconnect, then connect) in a level
  and checks the pause state and prompt device.

### B. The mouse cursor hides itself
- **Why:** the game has no mouse controls, but the cursor stays visible over the game, worst in
  fullscreen, where it sits in the middle of the screen.
- **Do:** hide the cursor once a key or pad button is used or after a couple of seconds still;
  show it again when the mouse moves.
- **Accept:** cursor hidden after keyboard or pad input and after 2 s without mouse movement;
  visible right after mouse movement.
- **Verify:** a headless unit check of the rule, and a windowed run that reads
  `DisplayServer.mouse_get_mode()` back (headless has no cursor).

### C. Assist → Air Dashes: Default / Two / Infinite
- **Why:** the assist menu has speed, stamina, invincibility and the Route Ghost, but no help
  with the game's central skill. Celeste's assist mode, the genre's reference, offers two or
  infinite air dashes, and many dash-heavy rooms (gems over spike pits, the Summit) are where
  players get stuck.
- **Do:** a new assist row. *Two* gives two dashes wherever the room gives at least one;
  *Infinite* never spends a dash. Rooms before the story gives Mira her dash stay dashless.
  The Route Ghost keeps running the proven default route.
- **Accept:** the setting changes the simulation as described, applies on the next step after
  the menu closes, survives respawns and room changes, and Default behaves exactly as today
  (all proofs and playthroughs unchanged).
- **Verify:** a headless check of the world with each setting (dashes after one, two and five
  dashes, prologue room stays at 0); ui_flow steps the row; the full suite; a screenshot.

### D. Controls in the pause menu
- **Why:** rebinding and Grab Mode are only on the title screen. A player who finds holding
  grab tiring halfway up a chapter, or a key awkward, has to quit to the title to change it.
- **Do:** move the controls panel into a shared piece both menus use, and add *Controls* to
  the pause screen's Options.
- **Accept:** rebinding a key, a pad button and Grab Mode from the pause menu behave as on the
  title (swaps, Reset Defaults, Esc/Start cancels) and take effect on resume. The title's
  controls screen is unchanged.
- **Verify:** ui_flow's existing title controls steps still pass on the shared code, plus new
  pause steps: rebind Jump, check it, toggle Grab Mode, Reset Defaults, resume. Screenshot.

### E. Route Ghost: show where she passes through your blocks (if A–D land cleanly)
- **Why:** round 3's known limit: a crumbling board or mask block that is solid for the player
  but not for her is drawn normally, so she seems to walk through a wall.
- **Do:** without hiding the player's own blocks, outline those cells in her tint while she is
  near them.
- **Accept:** only cells solid for the player and open for her, near her, are marked; nothing
  changes when the ghost is off.
- **Verify:** a unit check of the cell rule beside ui_flow's existing ghost-parts check, and a
  screenshot of 3-02 where her mask blocks have swapped.

Not picked: physical controllers and 144/165 Hz displays (no hardware here); builds, license
and releases (owner decisions); new content (too large).

## Round 5 results (2026-10-06)

All commits are on `improvements-5`; nothing has been pushed. The full suite passes after every
item (fastest-route and basic-moveset proofs, golden runs, end-to-end playthroughs, hint
replays, save check, menu flow). The final run took 58 s at load average 23–29. Every run used a
throwaway user-data directory under `build/`, and the real save's checksum was the same before
and after. Screenshots are in `docs/media/improvements/round5/`.

| Item | Status | Commit | Verified by |
|---|---|---|---|
| Round 4 flake: diagnostics | Done | `e43576b` | Not reproduced in 30 standalone runs (load up to 14). A forced failure now prints the frame, the relevant settings and the last 40 inputs that reached the scene. |
| A. A disconnecting controller pauses | Done | `2199230` | ui_flow: a disconnect during play opens the pause menu, releases the held direction and puts prompts back on the keyboard; a connect does nothing; a disconnect during a death pauses as soon as play resumes. Fails without the fix (`pad_paused`). |
| B. The cursor hides itself | Done | `58dc768` | ui_flow: hidden after a key, shown after mouse motion, still shown at 1.7 s, hidden at 2.2 s. A real window (Wayland) read back `DisplayServer.mouse_get_mode()`: hidden after a key, visible after motion, visible at 1 s, hidden at 2.5 s. |
| C. Assist → Air Dashes | Done | `596a375`, `ec33ff4` | A sim check in ui_flow: from a jump, three up-dashes fire 1 / 2 / 3 times for Default / Two / Infinite, after a respawn; the prologue's first room stays at 0 and the Summit at 2. ui_flow steps the menu row (clamps on Left/Right, wraps on Confirm) and checks the live world gets 2 dashes in 1-01. Every cached route replays unchanged at Default (`ec33ff4` only re-stamps the sim hash). Screenshot: `assist_air_dashes.png`. |
| D. Controls in the pause menu | Done | `9893593` | The title's existing controls steps pass on the shared `ControlsMenu`. New pause steps rebind Jump to M (checked in the input map), cancel a rebind with Esc while staying paused, toggle Grab Mode, use Reset Defaults (Grab Mode kept) and close. Screenshot: `pause_controls.png`. |
| E. Route Ghost: blocks she passes through | Done | `08c755d` | A unit check in ui_flow: with the player idle and the ghost running her route, the cells marked are only boards in 1-03 and only mask blocks in 3-02, none at the start, and the near ones are within the radius. A survey of all rooms: she overlaps such a block on 75 frames (3-01, 3-03, 3-04, 3-05, 7-04). Screenshot in 3-04: `ghost_open_blocks.png`. |

### Deviations and limits
- **Window focus** now uses the same pause as a disconnect: if focus is lost during a death,
  a room transition or a cutscene, the pause happens when play resumes instead of not at all.
  The scope only asked for controllers.
- **Air Dashes** applies to the chase rooms' Grin only indirectly: the Grin replays your moves,
  so it dashes as often as you do. Mask blocks still swap on every dash, so Infinite can swap
  them more often than a room expects. Neither was playtested.
- **The ghost outline** is drawn only within 28 px of her and fades with distance. In 1-03 her
  boards fall after she has left them, so they're never outlined. Whether it reads clearly to
  someone who hasn't read this note is a playtest question.
- **The cursor** check in a real window used synthetic mouse events, not a physical mouse.
- **Godot's import pass** (needed to register the new `ControlsMenu` class) also generated the
  missing `.uid` files for `tests/save_check.gd` and `tools/motion_probe.gd`; they're committed.
- One ui_flow step comment said the level after chapter select was the prologue; it's 1-01.
  The comment is fixed. The test was already checking 1-01.

### Still open
- The round 4 flake's cause (now with diagnostics if it recurs).
- A human playtest, physical controllers (including a real unplug) and a real 144/165 Hz display.
- **Owner decisions (unchanged):** export templates and Windows/web/macOS builds, signing and
  notarization, hosting, license, releases and tags, re-cutting the trailer. The v0.1.0 release
  still has the Game Speed, crash-save and stuck-Dash bugs that `main` fixes.

## Round 6 scope (2026-10-07)

Baseline on `improvements-6` (from `main` = `origin/main` = `8fef39d`): the full suite passes in
55 s at load average 21. All runs this round use a throwaway user-data directory (the suite's
`build/test_user/`, or `build/r6/` for probes), and the real save's checksum is compared before
and after.

**Probes for this plan (throwaway, in the git-ignored `build/r6/`):**
1. *Frame times.* Chapters 1, 3, 6 and 7 played through the real Level scene in a window with
   the proven routes, vsync off, at load average 2–20: median 6.9 ms, 99th percentile 7.3–8.6 ms.
   The only frames over 20 ms are the first one of a chapter (64–370 ms, behind the opening
   wipe). No performance item is needed on this hardware.
2. *Keyboard layouts.* Bindings use physical key positions (good: WASD and the C/X/Z cluster stay
   where they are on any layout), but every prompt names the key by its US-QWERTY label. Run
   inside a private, invisible KWin session with its own D-Bus and a French layout, Godot reports
   physical W, A and Z as **Z, Q and W**; with German, Z is **Y**. So a French player is told
   "Hold Z to GRAB" when the key to press is printed W, and the HUD, pause hints, Controls screen
   and the Route Ghost's strip all disagree with the keyboard.

Picked for a real player's experience, and because each can be checked here:

### A. Prompts name the keys printed on the player's keyboard
- **Do:** name keys through the active layout (`DisplayServer.keyboard_get_keycode_from_physical`)
  everywhere a key is shown (signs, hints, Controls, the ghost's strip). Labels the pixel font
  can't draw (non-ASCII, such as a Cyrillic letter) fall back to the US name, which is what most
  such keyboards print beside it.
- **Accept:** on US layouts nothing changes; on French the default Grab key reads W and Up/Left
  read Z/Q; on German Grab reads Y. Bindings themselves stay positional.
- **Verify:** a ui_flow unit check with a stubbed layout map (fr and de cases, the non-ASCII
  fallback, and identity on US); the real labels read back from Godot under a private KWin
  session with French and German layouts; a screenshot of the prologue's grab sign under French.

### B. Route Ghost: Berries
- **Why:** collecting is most of the replay value (61 berries, 7 bells), and the ghost only shows
  the way to the exit. A player missing one berry in a room has no help at all.
- **Do:** the Assist row becomes *Route Ghost: Off / Exit / Berries*. In *Berries* the ghost runs
  the suite's proven basic-moveset route that takes every collectible in the room while any of
  them is still missing; otherwise, if a secret room off this room still holds something
  missing, the route into it; otherwise the exit route. The goal is chosen again each time she
  loops, so it moves on once the player has the berries. The button strip names her goal.
  Routes ship in `data/hints.json` beside the exit routes.
- **Accept:** every room/spawn with collectibles has a berries route, and every room/spawn with a
  door to a secret room has a route into it; each replays to its exit with no advanced tech and
  picks up everything it claims. Exit mode behaves exactly as today. Old settings files
  (`route_ghost: true`) read as *Exit*.
- **Verify:** `hints_check.gd` replays the new entries and checks what they collect (and flags a
  corrupted one); the suite fails if a route is missing; ui_flow steps the row (Off/Exit/Berries,
  clamping and wrap) and checks the goal picked in 1-02 with nothing, some and everything
  collected; screenshots.

### C. Results show a new Best
- **Why:** the results screen shows the run's time but never says whether it beat your Best, or
  why a checkpoint run didn't count, which is the main thing a returning player looks for.
- **Do:** on a full run, show *New Best!* when it sets Best, or the Best it didn't beat. On a run
  started from a checkpoint, say it was a practice run (no Best), matching chapter select.
- **Accept:** the three cases show the right line; nothing else on the screen moves.
- **Verify:** ui_flow checks the results rows for a first full run, a slower one and a practice
  run (the existing results steps already finish chapters both ways); screenshots.

### D. Mouse in menus (stretch, only if A–C land cleanly)
- **Why:** the game has no mouse controls, so a PC player who clicks a menu row gets nothing.
- **Do:** hovering a row selects it and clicking confirms it, in the title, options, pause,
  assist and options screens. Keyboard and pad behaviour unchanged; the cursor still hides in play.
- **Verify:** ui_flow sends mouse motion and clicks to those menus.

Not picked: physical controllers and 144/165 Hz displays (no hardware here); builds, license
and releases (owner decisions); new content (too large); performance (probe 1).

## Round 6 results (2026-10-07)

All commits are on `improvements-6`; nothing has been pushed. The full suite passes after every
item (fastest-route and basic-moveset proofs, golden runs, end-to-end playthroughs, hint
replays, save check, menu flow). The final run took 66 s at load average 23–35, and ui_flow then
passed three more standalone runs at load 35–79. Probe windows ran inside a private, invisible KWin session
(`kwin_wayland --virtual` with its own D-Bus and sandboxed config and user data), so nothing
opened on the desktop and the desktop's keyboard layout was never touched. Screenshots are in
`docs/media/improvements/round6/`.

| Item | Status | Commit | Verified by |
|---|---|---|---|
| A. Prompts name the keys printed on the keyboard | Done | `865644c` | A ui_flow unit check with stand-in French, German and Cyrillic layouts and none (fails without the fix). Under real layouts in the private KWin, Godot read back Grab = **W**, W/A = **Z/Q** (French), Grab = **Y** (German) and the US names unchanged. Screenshot of the prologue's grab sign under US, French and German: `sign_keyboard_layouts.png`. |
| B. Route Ghost: Berries | Done | `5831813` | The suite now ships 132 routes (71 exit, 52 collect, 9 secret) and fails on a gap. `hints_check.gd` replays every one with the basic moveset and checks each collect route picks up what it lists; two deliberately corrupted entries were caught. ui_flow checks the goal rule in 1-02, 1-05, 1-05s and 3-01, that old settings read as Exit, and steps the row (Exit → Berries, clamp, back, wrap to Off) with the ghost running 1-01's collect route; a mutated goal rule fails it. Screenshots: `route_ghost_berries.png` (her touching berries in 1-02 and 2-02, heading for 1-05's secret room, and *To the exit* once all is found), `assist_route_ghost_berries.png`. |
| C. Results say whether it's a new Best | Done | `730c016` | ui_flow runs the Best rule on a first, faster, slower and checkpoint run and checks both the row and the saved Best. Screenshots of a new Best (six rows: bell and golden too), a slower climb and a checkpoint run: `results_best.png`. |
| D. Mouse in menus (stretch) | Done | `5e3693e` | ui_flow points at and clicks rows on the title, Options, pause and Assist screens (hover selects, a click off the rows does nothing, left-click confirms, right-click backs out) and clicks through the results screen; with the pause menu's mouse code disabled it fails. In a real window at 3× scale, events in window pixels sent through `Input` selected the right row, opened Options and backed out. |

### Deviations and limits
- **Checkpoint and Continue runs** both show "Best: full climbs only" on the results screen. The
  scope said "practice run", but a continued climb isn't one, and Best is for full climbs in
  both cases.
- **Berries mode** draws only the player's berries, so the ghost runs through them, or through
  the spot where a berry the player already has used to be. Her collect route takes every berry
  in the room even when only one is missing (it's the one proven route). The golden berry alone
  doesn't count as missing (it sits at the chapter start in plain sight).
- **Mouse:** the scope listed "title, options, pause, assist and options"; that meant the title's
  main menu and Options plus the pause, Assist and pause-Options panels, and the results screen
  was added. Chapter select, Controls and the confirm boxes stay keyboard and pad only. No
  physical mouse was used.
- **Keyboard layouts:** checked under Wayland only. X11 (Xwayland) ignored a layout uploaded with
  `xkbcomp`, so the X11 path wasn't checked; Windows and macOS builds don't exist yet.
- **A sandboxing slip.** The first five keyboard probes (06:51–06:52) ran Godot without the
  redirected user-data path. They wrote only engine log files to the real
  `~/.local/share/godot/app_userdata/Jeste/logs/`, and Godot's five-file log rotation will have
  removed older logs there. The real save's checksum is unchanged and no settings file was
  created. Every later run was sandboxed.

### Still open
- A human playtest (Air Dashes, ghost outlines and now Berries mode), physical controllers, a
  physical mouse, a real 144/165 Hz display, and a non-US keyboard in hand.
- The round 4 menu-flow flake (not seen this round).
- **Owner decisions (unchanged):** export templates and Windows/web/macOS builds, signing and
  notarization, hosting, license, releases and tags, re-cutting the trailer. The v0.1.0 release
  still has the Game Speed, crash-save and stuck-Dash bugs that `main` fixes, and now the
  wrong key names on non-US keyboards.

## Round 7 scope (2026-10-07)

Baseline on `improvements-7` (from `main` = `origin/main` = `0b525a8`): the full suite passes in
30 s at load average 6. All runs this round use a throwaway user-data directory (the suite's
`build/test_user/`, or `build/r7/` for probes, with `TMPDIR` in `build/r7/tmp/` so the suite's
scratch files stay off the shared `/tmp`). The real user-data folder's checksums (save and the
log files there) were recorded before the first run and are compared at the end.

**What the code shows (read for this plan):**
1. *A mouse player gets stranded.* Round 6 made the title, Options, pause, Assist and results
   take the mouse, but *Climb* leads to chapter select, which ignores it; so do Controls, the
   Erase Save and Restart Chapter boxes, and cutscenes (a click doesn't advance a line).
2. *A click can only raise the volume.* A left click on a menu row is Confirm, and Confirm on
   Music or Sound Volume adds 10% and stops at 100%. With the mouse alone there's no way to
   turn either down.
3. *The ghost's berries.* In Berries mode she takes berries in her own simulation, but only the
   player's are drawn, so nothing shows her taking them (round 6's known issue).
4. *No fullscreen key.* Fullscreen is only in the Options menus; F11 and Alt+Enter do nothing.

Picked for a real player's experience, and because each can be checked here:

### A. Mouse in chapter select and the checkpoint picker
- **Do:** click a chapter's marker on the trail (or the side arrows) to select it, click the card
  to choose it, right-click to go back. In the picker, click the postcard's arrows or a reached
  room's pip to pick a checkpoint, click the card to start, right-click to close it.
- **Accept:** a mouse alone gets from the title to a level and back; locked chapters and
  unreached rooms can't be picked by clicking; keyboard and pad behaviour unchanged.
- **Verify:** ui_flow clicks through chapter select and the picker (marker, arrow, locked marker,
  pip, unreached pip, card, right-click), and the existing key steps still pass; screenshot.

### B. Mouse in Controls, confirm boxes, cutscenes and sliders
- **Do:** Controls rows take hover and click (a click starts a rebind; right-click cancels a
  rebind or closes the panel). Restart Chapter's two choices take hover and click; Erase Save's
  *Erase* and *Keep* prompts are clickable (a click elsewhere does nothing, so a stray click can't
  erase a save). A left click advances a cutscene line. A click on a volume slider sets the
  volume where you clicked.
- **Accept:** each of these works by mouse alone; mouse buttons can't be bound as keys; a click on
  the Erase Save box away from *Erase* erases nothing.
- **Verify:** ui_flow steps for each (title Controls, pause Controls, both confirm boxes, a
  cutscene line, both sliders down to 0% and back up), fails with the new code disabled.

### C. Route Ghost draws her own berries, bells and keys
- **Do:** draw, in her tint, the collectibles and keys of her simulation where they differ from
  the player's: hers still in place where the player's is gone or already collected (drawn as an
  outline), and hers following her once she has touched them.
- **Accept:** in 1-02 (Berries mode) her berry is drawn following her after she touches it, and
  nothing extra is drawn where both are untouched; nothing changes with the ghost off.
- **Verify:** a ui_flow unit check of which items are drawn for her, a survey over the collect
  routes, screenshots.

### D. F11 and Alt+Enter toggle fullscreen
- **Do:** either key toggles fullscreen anywhere (and is saved), unless the player has bound that
  key to a game action. Alt+Enter doesn't also pause or confirm.
- **Accept:** works on the title, in chapter select and in play; Alt+Enter in play doesn't open
  the pause menu; F11 bound to Jump doesn't toggle; while rebinding, F11 is taken as the new key.
- **Verify:** ui_flow steps for each case.

### E. Keyboard layouts under X11 (stretch, a check rather than a change)
- **Do:** repeat round 6's French and German key-name check with Godot's X11 driver inside a
  private KWin session's Xwayland. If the names are wrong there, fix or document it.
- **Verify:** the label read back under X11; otherwise say why it couldn't be checked.

Not picked: physical controllers, a physical mouse and 144/165 Hz displays (no hardware here);
builds, license and releases (owner decisions); new content (too large).

## Round 7 results (2026-10-07)

All commits are on `improvements-7`; nothing has been pushed. The full suite passes after every
item (fastest-route and basic-moveset proofs, golden runs, end-to-end playthroughs, hint
replays, save check, menu flow). The final run took 60 s at load average 22–25, and ui_flow then passed three more standalone runs at load 23–25. Every run used a throwaway
user-data directory (`build/test_user/` or `build/r7/`), with `TMPDIR` in `build/r7/tmp/`, and
the real user-data folder (save and log files) had the same checksums before and after. Window
probes ran inside a private, invisible KWin session (`kwin_wayland --virtual`, adding
`--xwayland` for X11, with its own D-Bus and sandboxed config and user data, and the outer
`DISPLAY` and `WAYLAND_DISPLAY` removed), so nothing opened on the desktop. Screenshots are in
`docs/media/improvements/round7/`.

| Item | Status | Commit | Verified by |
|---|---|---|---|
| A. Mouse in chapter select and the picker | Done | `f6fb9a8` | ui_flow: a right click goes back to the title; a locked chapter's marker can't be clicked; markers, both side arrows and a click on nothing; a click on the card opens the picker; a reached pip, an unreached pip (nothing), the postcard's arrows, a right click closing the picker, and a click on the card starting the level at that checkpoint. Fails with the mouse code disabled. In a real window: `mouse_menus.png` (top left). |
| B. Mouse in Controls, confirm boxes, cutscenes, sliders | Done | `6c5a35e` | ui_flow: volume sliders set to 0%, 50%, 80% and back by clicks (the label still steps); Erase Save asks, ignores a click off its prompts, keeps on *Keep* and on a right click, erases on *Erase*; title Controls: hover, a click starts a rebind, a second click can't be bound, a right click cancels, Grab Mode toggles by click, a right click closes; pause Controls hover and right-click close; the pause sliders; the Restart box's hover, a click off it, a right click backing out and a click on *Restart*; a click reads the next cutscene line. Five mutations (each piece disabled, and a naive Erase box that confirms on any click) each fail it. Real window: `mouse_menus.png`. |
| C. Route Ghost draws her own berries, bells and keys | Done | `b73a2f2`, `74ffc32` | A ui_flow unit check on her collect routes in 1-03 (two berries) and 3-05 (two berries, two keys): nothing extra is drawn while the player touches nothing except what she carries, she carries every berry and key, and berries the player found earlier are drawn for her until she takes them. Two mutations fail it. A survey of all 52 collect routes: no unexpected item on any frame, and she visibly carries every berry in each room. Screenshot (1-03 and 3-05, her berry trailing her while the player's stays): `route_ghost_carries_berries.png`. |
| D. F11 and Alt+Enter toggle fullscreen | Done | `7507e6e` | ui_flow: both keys on the title (Alt+Enter doesn't choose *Climb*), in chapter select and in play (Alt+Enter doesn't pause); while rebinding (title and pause), F11 becomes the binding; bound to Jump it acts as Jump. Three mutations fail it. A real window under Wayland and under X11 (Xwayland) switched to fullscreen and back. |
| E. Keyboard layouts under X11 | Checked, no change needed | `369af81` | Under the private KWin's Xwayland with Godot's X11 driver: French reads Grab = **W**, W/A = **Z/Q**; German reads Grab = **Y**; US unchanged. Screenshot of the prologue's grab sign under X11: `x11_keyboard_layouts.png`. |

### Deviations and limits
- **Mouse:** hover selects rows as before, but on chapter select only a click changes the
  chapter (hovering the trail would repaint the backdrop under the pointer). After a right
  click closes a box, the row under the pointer is selected, as any mouse movement would.
  There's no mouse wheel, gameplay stays keyboard and pad only, and no physical mouse was used.
- **Erase Save** takes a click on its prompts rather than on rows, so its keyboard and pad
  behaviour (Jump erases, Dash keeps) is unchanged.
- **Route Ghost:** a berry the player already found is drawn for her over its outline in her
  tint, which is faint against the outline sprite; once she takes it, it trails her clearly.
  Her dash gems and balloons are still not drawn separately. Not playtested.
- **F11** that a player has bound to Jump (or any action) does that action instead; Alt+Enter
  always toggles. Neither works in a web build (the browser owns those keys), and there is no
  web build yet.
- **X11:** checked in a private session's Xwayland, not on a real X11 desktop. There the X11
  window started maximised rather than at its 3× size (the Wayland window didn't); the cause
  wasn't looked into.
- **Test tooling:** `run_tests.py` writes its scratch JSON to the system temp folder; this round
  pointed `TMPDIR` at `build/r7/tmp/` rather than changing the runner.
- **Load:** several suite and ui_flow runs happened at load average 24–36 (the machine is
  shared). ui_flow runs at a fixed 60 fps, so this slowed it without changing its result; the
  final runs are listed above with their load.

### Still open
- A human playtest (Air Dashes, ghost outlines, Berries mode and her carried berries),
  physical controllers, a physical mouse, a real 144/165 Hz display, and a non-US keyboard in
  hand.
- The round 4 menu-flow flake (not seen this round).
- **Owner decisions (unchanged):** export templates and Windows/web/macOS builds, signing and
  notarization, hosting, license, releases and tags, re-cutting the trailer. The v0.1.0 release
  still has the Game Speed, crash-save and stuck-Dash bugs that `main` fixes, and the wrong key
  names on non-US keyboards.

## Round 8 scope (2026-10-07)

Baseline on `improvements-8` (from `main` = `origin/main` = `2871e89`): the full suite passes in
23 s at load average 3. All runs this round use a throwaway user-data directory (the suite's
`build/test_user/`, or `build/r8/` for probes), with `TMPDIR` in `build/r8/tmp/` so scratch
files stay off the shared `/tmp`. The real user-data folder's checksums (save and log files)
were recorded before the first run and are compared at the end. Window probes run inside a
private, invisible KWin session as in round 7.

**What the code and a probe show (read for this plan):**
1. *Her gems and balloons.* A survey of all 132 ghost routes against an idle player: in 15 rooms
   (26 routes, chapters 1, 2, 3, 5, 6 and 7) her dash gems or balloons are in a different state
   from the player's for 21–282 frames per route. Only the player's are drawn, so a gem she has
   just used still sparkles as ready, and the balloon she's riding sits idle.
2. *A berry the player already found* is drawn for her (round 7) as her tinted berry over the
   player's found-berry outline. In a 1-03 screenshot it reads as a grey blob, not as hers.
3. *Mouse wheel.* No screen reads it. Chapter select and the checkpoint picker can only be
   browsed by clicking small markers and arrows, volume sliders need a click at the right spot,
   and the credits ignore the mouse entirely (no click, no scroll).
4. *X11 window size.* In round 7's private KWin session (a 1280×720 screen) the X11 window
   started maximised instead of at its 3× size. The project's first window is 1280×720 before
   the game resizes it, which is the whole of that screen.

Picked for a real player's experience, and because each can be checked here:

### A. Route Ghost draws her own dash gems and balloons
- **Do:** where her gem or balloon differs from the player's, draw hers in her tint: one she has
  used (the player's still ready) gets a ring in her tint that drains until hers comes back; one
  that is ready for her but spent for the player is drawn whole in her tint; the balloon she's
  riding squashes in her tint.
- **Accept:** with the player idle, a gem or balloon she uses is marked for exactly as long as
  hers is gone; with the player having used one she hasn't, hers is drawn; nothing extra is
  drawn where both match, and nothing with the ghost off.
- **Verify:** a ui_flow unit check of the rule on 1-04 (three gems) and 5-02 (three balloons)
  both ways round, which a mutated rule fails; a survey of all routes (every marked frame
  matches the sim state); screenshots in 1-04 and 5-02.

### B. Berries she still has to take read as hers
- **Do:** give her berries, bells, keys and golden berry a soft halo in her tint, and draw the
  ones sitting over the player's found-berry outline strongly enough to read as hers.
- **Accept:** in 1-03 with one berry found, her berry over its outline is clearly in her colour
  (measured on the screenshot against the outline alone and against the round 7 drawing); her
  carried berries still read as before; nothing changes with the ghost off.
- **Verify:** before/after screenshots and a pixel measurement of the berry's spot; round 7's
  ghost-items check still passes.

### C. Mouse wheel in menus and the credits
- **Do:** on chapter select the wheel moves between chapters, and in the checkpoint picker
  between checkpoints. Over a volume slider or a multi-choice row (Window Size, Smooth Motion,
  Game Speed, Air Dashes, Route Ghost) it steps the value; elsewhere in a list it moves the
  selection. The credits scroll with the wheel and take a click as Confirm. A touchpad's
  fractional scroll steps add up, so a notch is one step. Gameplay ignores the wheel, and it
  can't be bound in Controls.
- **Accept:** each of those works by wheel alone, one notch per step, without unlocking a locked
  chapter or an unreached checkpoint; keyboard, pad and click behaviour unchanged.
- **Verify:** ui_flow wheel steps on each screen, including fractional (touchpad) events and a
  wheel during play and while rebinding; fails with the wheel code disabled.

### D. The first window on small and X11 screens (a check, fixed if simple)
- **Do:** find why the X11 window started maximised; if it is the 1280×720 first window filling
  a 1280×720 screen, start smaller so the game's own sizing decides.
- **Verify:** read back the window mode and size under Wayland and X11 (Xwayland) in a private
  KWin session with 1280×720, 1366×768 and 1920×1080 screens, before and after.

Not picked: physical controllers, a physical mouse and 144/165 Hz displays (no hardware here);
builds, license and releases (owner decisions); new content (too large); mouse control of
gameplay itself (keyboard and pad are the game's controls, as in the genre).

## Round 8 results (2026-10-07)

All commits are on `improvements-8`; nothing has been pushed. The full suite passes after every
item (fastest-route and basic-moveset proofs, golden runs, end-to-end playthroughs, hint
replays, save check, menu flow). The final run took 60 s at load average 21–25, and ui_flow then
passed two more standalone runs at load 23. Every run used a throwaway user-data directory
(`build/test_user/` or `build/r8/`), with `TMPDIR` in `build/r8/tmp/`, and the real user-data
folder (save and log files) had the same checksums before and after. Window probes ran inside a
private, invisible KWin session (`kwin_wayland --virtual`, adding `--xwayland` for X11, with its
own D-Bus and sandboxed config and user data, and the outer `DISPLAY` and `WAYLAND_DISPLAY`
removed), so nothing opened on the desktop. Screenshots are in
`docs/media/improvements/round8/`.

| Item | Status | Commit | Verified by |
|---|---|---|---|
| A. Route Ghost draws her own dash gems and balloons | Done | `91ce03f` | A ui_flow unit check in 1-04 (gems) and 5-02 (balloons), once with her running and the player idle and once the other way round: on every frame exactly the gems and balloons whose state differs are reported, as *used*, *ready* or *riding*, and each state turns up. Two mutations (no *ready* gems, no *riding*) fail it. A survey of all 132 routes both ways round (264 runs, 17 rooms): every reported entry matches the sim. Screenshot of the draining rings in 1-04 and 5-02: `route_ghost_gems_balloons.png`. |
| B. Her berries read as hers | Done | `e105a41` | Her items are now pale, dark-rimmed shapes in her colour (`Art.objects_ghost`). In 1-03 with one berry found, the brightest third of the berry's spot was beige (203, 181, 148) in round 7 and is now pale cyan (201, 227, 235): its distance from her tint (178, 230, 255) went from 120 to 31 (the found-berry outline alone is 60). ui_flow checks the sheet (berry pixels grey, a dark rim) beside round 7's items check. Before/after and carried: `route_ghost_found_berry.png`. |
| C. Mouse wheel in menus and the credits | Done | `c324cd8` | ui_flow: the title list (a notch, three 0.4 touchpad steps adding up to one, back up); a slider stepped up and down and the wheel moving past Fullscreen without toggling it; Controls, and a pending rebind that ignores it; chapter select (steps chapters, can't reach a locked one) and the picker (steps checkpoints, stops at the last); pause list, Route Ghost stepped Off → Exit → Off and the wheel moving past Invincibility; a pause slider; the Restart box ignoring it; play ignoring it; the credits scrolling ±40 px, a click skipping ahead and a right click leaving. Five mutations (no touchpad accumulation, no chapter-select wheel, no credits wheel, hover on a wheel event, no Controls wheel) each fail it. In a real 3× window, wheel events in window pixels moved the title selection, stepped Music Volume and added three 0.34 steps up to one. |
| D. The first window on small and X11 screens | Fixed | `34fcb21` | Window mode and size read back in the private KWin at 1280×720, 1366×768 and 1920×1080 under Wayland and X11. Before: X11 at 1280×720 opened maximised (1280×692), because the 1280×720 first window filled the screen; the other five were windowed at their Auto size. After (first window 640×360): all six windowed at their Auto size (960×540, 960×540, 1280×720), the X11 ones centred. |

### Deviations and limits
- **B went further than planned.** The scope asked for a halo and a stronger drawing over a found
  berry. A halo didn't fix the colour (her tint over the orange berry is still brownish), so all
  her items, and the gems and balloons from A, use the pale shapes instead; no halo.
- **The wheel over a value row** steps the value only for sliders and multi-choice rows (volume,
  Window Size, Smooth Motion, Game Speed, Air Dashes, Route Ghost); over an on/off row it moves
  the selection, so a stray scroll can't flip Fullscreen or Invincibility. Wheel up is "more".
  On chapter select, wheel down is the next chapter. Results screens and cutscenes ignore the
  wheel (a scroll shouldn't skip a line). A wheel event still shows the mouse cursor in play,
  like any mouse event. Horizontal scrolling is ignored.
- **Touchpads:** the accumulation was checked with synthetic `factor` values; no real touchpad
  was used, and how much each platform reports per swipe varies.
- **The first window** is now 640×360 for a moment before the game sizes it, on every screen
  (it was 1280×720). Only KWin was tried; other window managers may place or maximise windows
  differently. Debug tools that skip the game's window sizing (`tools/shot.tscn` and others)
  now open at 640×360; their captures come from the 320×180 viewport, so they're unchanged.
- **Shared `/tmp`:** 3.4 GB of trailer captures from 2026-10-04 (`/tmp/jeste_movie*`,
  `/tmp/jeste_cred`) are still on the shared RAM disk. They predate this round, so they were
  left alone.

### Still open
- A human playtest (Air Dashes, ghost outlines, Berries mode, her pale items and rings),
  physical controllers, a physical mouse and touchpad, a real 144/165 Hz display, and a non-US
  keyboard in hand.
- The round 4 menu-flow flake (not seen this round).
- **Owner decisions (unchanged):** export templates and Windows/web/macOS builds, signing and
  notarization, hosting, license, releases and tags, re-cutting the trailer. The v0.1.0 release
  still has the Game Speed, crash-save and stuck-Dash bugs that `main` fixes, the wrong key names
  on non-US keyboards, and now the maximised window on 720p X11 screens.

## Round 9 scope (2026-10-07)

Baseline on `improvements-9` (from `main` = `origin/main` = `3d0f181`): the full suite passes in
26 s at load average 7. All runs this round use a throwaway user-data directory (the suite's
`build/test_user/`, or `build/r9/` for probes), with `TMPDIR` in `build/r9/tmp/` so scratch
files stay off the shared `/tmp`. The real user-data folder's checksums (save and log files)
were recorded before the first run and are compared at the end. Window probes run inside a
private, invisible KWin session as in rounds 7 and 8.

**Probes for this plan (throwaway, in the git-ignored `build/r9/`):**
1. *Random play in every room.* 2.7 million simulation steps of random held inputs (run, jump,
   8-way dash, grab and climb, 1–24 frames each), 20 walks of 2,000 steps from every spawn of all
   69 rooms. After every step, Mira was never inside a solid block (outside a dash) and never
   outside a room without having died or left by an exit. No bug found.
2. *Invincibility doesn't stop every death.* The same walks with Assist → Invincibility on: the
   only deaths left are falls into a bottomless pit (0-02, 0-05 and 0-06 in the prologue, and
   7-05s) and dashing out of a velvet curtain into a wall (7-03). Spikes, the Grin and gondola
   crushes are already covered. So a player who turns it on to get past the prologue still dies
   in its pits, and a curtain crash in chapters 2, 5 and 7 still sends you back.
3. *Colour vision.* Mira's cap shows the dash state by colour (red ready, blue spent, pink two).
   Simulated protanopia, deuteranopia and tritanopia keep every pair at least 21 CIELAB units
   apart, with a lightness gap too, so no change is needed there.
4. *The assist list.* Game Speed, Infinite Stamina, Air Dashes and Invincibility match the
   genre's usual set, but there's no help for players who can't aim a dash in time, the one
   input the whole game is built on. The Assist rows also don't say what they do; *Air Dashes:
   Two* and *Route Ghost: Berries* are only explained in the README.

Picked for a real player's experience, and because each can be checked here:

### A. Invincibility also catches falls and curtain crashes
- **Do:** with Invincibility on, falling out of the bottom of a room where there is no exit
  bounces Mira back up into the room with her dash and stamina refilled, and a dash through a
  curtain that would crash into a wall turns her round, back the way she came. Off, nothing
  changes.
- **Accept:** with Invincibility on, the random walks of probe 2 never die; with it off they die
  as before; every cached route replays unchanged.
- **Verify:** probe 2 rerun on all rooms; a sim check in ui_flow (a fall in 0-02 and a crash in
  7-03 survive with it on and die with it off) that fails without the change; the full suite.

### B. Assist → Dash Aim
- **Do:** a new Assist row, *Dash Aim: Off / On*. On, pressing Dash when a dash would start
  stops time (the simulation, her Route Ghost and the chapter timer) and shows an 8-way arrow
  around Mira pointing where the dash will go. Holding a direction turns it; letting go of Dash
  dashes that way (the last direction held, or straight ahead if none). A press that wouldn't
  dash (none left, or mid-dash) behaves as before. Pausing while aiming keeps the aim.
- **Accept:** with it on, the world doesn't step while Dash is held, and the dash on release goes
  in the direction aimed, also when the direction is let go a frame before Dash; with it off,
  play is unchanged (the end-to-end playthroughs and the Route Ghost don't use it).
- **Verify:** ui_flow steps the row and drives a held Dash in play (no steps while held, an
  up-right dash on release, the arrow showing, the chapter timer stopped), and a press with no
  dash left doesn't freeze; fails with the code disabled; a screenshot of the arrow.

### C. Assist rows say what they do
- **Do:** under the Assist panel, one or two lines describe the highlighted row, including
  what each value of Air Dashes and Route Ghost means.
- **Accept:** every Assist row has a line that fits the 320 px screen in the pixel font.
- **Verify:** a ui_flow check that every row has a description and that each line fits;
  screenshots of the panel.

Not picked: physical controllers, a physical mouse and 144/165 Hz displays (no hardware here);
builds, license and releases (owner decisions); new content (too large). Descriptions for the
Options rows would need the panel redrawn (it already reaches the hints line) and are left for
later.

## Round 9 results (2026-10-07)

All commits are on `improvements-9`; nothing has been pushed. The full suite passes after every
item (fastest-route and basic-moveset proofs, golden runs, end-to-end playthroughs, hint
replays, save check, menu flow). The final run took 68 s at load average 31–38, and ui_flow then
passed two more standalone runs at load 28–33 (it runs at a fixed 60 fps, so load slows it
without changing its result). Every run used a throwaway user-data directory
(`build/test_user/` or `build/r9/`), with `TMPDIR` in `build/r9/tmp/`, and the real user-data
folder (save and log files) had the same checksums before and after. Window captures ran inside
a private, invisible KWin session as in round 8. Screenshots are in
`docs/media/improvements/round9/`.

| Item | Status | Commit | Verified by |
|---|---|---|---|
| A. Invincibility catches pit falls, curtain crashes and gondola crushes | Done | `257b46b` | Probe 2 rerun: 5.4 million random steps in all 69 rooms with Invincibility on, no deaths, never inside a wall or outside a room. Off, the same walks die 27,574 times and still never end up inside a wall or outside a room. A curtain survey (from every free spot two tiles off a curtain, a dash in each of 8 directions, 2,056 of them through a curtain): 1,148 deaths off, none on, none left stuck in a curtain. A ui_flow sim check (a fall in 0-02, a crash in 7-03, a gondola pushing Mira into 4-02's wall) dies off and survives on, never inside anything; each of the three parts disabled fails it. All 266 cached routes replay with identical inputs (the files only carry the new sim hash). |
| Found on the way: closing the pause menu jumped or dashed | Fixed | `77dedc7` | A probe with real key events in 1-02: choosing Resume with Jump made Mira jump on the next step, and closing the menu with Dash (the pause screen's own hint for Resume) made her dash; both since v0.1.0. ui_flow now holds Jump on Resume and Dash for 20 frames each (nothing fires), checks a fresh Jump still jumps, and holds Jump as a cutscene closes (nothing fires). It fails without the fix, and with only the cutscene part removed. |
| B. Assist → Dash Aim | Done | `940f3a9` | ui_flow with real keys: the row toggles; holding Dash stops the world's frame count and the chapter timer; Up+Right let go one key at a time still dashes up-right; a stick rolled from Up-Right to Up dashes up; a press with no dash left doesn't aim; a pause drops the aim and nothing fires on resume. Four mutations (feature off, no grace, no "would a dash start" test, pause keeping the aim) each fail it. The test that asks the world whether a dash would start was asked 20,949 times along all 132 Route Ghost routes and left the world identical every time; ui_flow repeats this on five rooms, and a broken restore fails it. Screenshot: `dash_aim.png` (1-04 up-right, 2-02 up-left). |
| C. Assist rows say what they do | Done | `7e9ec50` | ui_flow: all 11 texts (7 rows, plus the other Air Dashes and Route Ghost values) are different, at most two lines, and fit 300 px in the pixel font; dropping one fails it. Screenshot: `assist_help.png`. |

### Deviations and limits
- **A went further than planned.** The scope named pits and curtains. The random walks then
  found a third death that Invincibility didn't stop, an older bug: a gondola crushing Mira into
  a wall left her inside it, stuck until Retry Room. She is now moved to the nearest free spot
  within 3 tiles (she dies if there's none). They also found a rare escape with or without the
  assist: a horizontal dash at exactly the bottom edge carried her under the floor and past a
  side wall, where she fell for ever. Being just out of sight below a floor with no exit now
  counts as a fall. If a curtain crash's way back is blocked too, she dies rather than bouncing
  inside the curtain. The pit bounce reaches about 7 tiles and refills her dash.
- **Dash Aim:** the scope said pausing would keep the aim; it drops it instead, because resuming
  with Dash already let go would have fired the dash at once. The row sits after Air Dashes,
  so Invincibility and Route Ghost moved down one (ui_flow's mouse positions were updated).
  While aiming, effects, the cap's tails and the music carry on; only the game world stops.
  Nobody has played it by hand, on a keyboard or a pad.
- **The pause fix** applies to Jump and Dash, the two keys menus and cutscenes use. If a player
  pauses mid-jump with Esc and resumes while still holding Jump, the held jump counts as
  released until they let go, so that jump ends early.
- **C:** the help replaces the panel's old tagline, which now shows on *Back*. The Route Ghost's
  button strip is hidden while the Assist panel is open (the text overlapped it). Options rows
  still have no descriptions.
- **Colour vision (probe 3)** was a calculation on the three cap colours, not a check with
  players.

### Still open
- A human playtest (Dash Aim, the invincible bounce, Air Dashes, ghost outlines, Berries mode),
  physical controllers, a physical mouse and touchpad, a real 144/165 Hz display, and a non-US
  keyboard in hand.
- Descriptions for the Options rows.
- **Owner decisions (unchanged):** export templates and Windows/web/macOS builds, signing and
  notarization, hosting, license, releases and tags, re-cutting the trailer. The v0.1.0 release
  still has the Game Speed, crash-save and stuck-Dash bugs that `main` fixes, the wrong key names
  on non-US keyboards, the maximised window on 720p X11 screens, and now the jump or dash on
  closing the pause menu and the deaths Invincibility missed.
