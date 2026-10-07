<p align="center">
  <img src="docs/media/teaser.gif" alt="Gameplay loop: Mira launches from circus balloons at the summit, bounces off pinball bumpers, outruns her reflection through velvet curtains, rides a gondola and flies past stained glass" width="100%">
</p>

<h1 align="center">JESTE</h1>

<p align="center">
  <b><i>A mountain that laughs back.</i></b><br>
  An original pixel-art precision platformer about a young jester climbing a mountain that shows you whatever you hide behind your smile.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/engine-Godot%204.7-478cbf?logo=godotengine&logoColor=white" alt="Engine: Godot 4.7">
  <img src="https://img.shields.io/badge/platform-Linux-f2c14e?logo=linux&logoColor=black" alt="Platform: Linux">
  <img src="https://img.shields.io/badge/language-GDScript-355570" alt="Language: GDScript">
  <img src="https://img.shields.io/badge/version-0.1.0-d8344f" alt="Version 0.1.0">
  <img src="https://img.shields.io/badge/every%20room-proven%20beatable-6fbf73" alt="Every room proven beatable">
</p>

<p align="center">
  <a href="https://github.com/nearbycoder/Jeste/releases/latest"><b>Download for Linux</b></a> ·
  <a href="docs/media/jeste_trailer.mp4"><b>Watch the trailer</b></a> ·
  <a href="#build-from-source"><b>Build from source</b></a>
</p>

## Trailer

<p align="center">
  <a href="docs/media/jeste_trailer.mp4">
    <img src="docs/media/trailer_poster.png" alt="Play the Jeste feature trailer (1:48)" width="100%">
  </a>
  <br><sub>The 1:48 feature trailer (1080p60 MP4, 38 MB): <a href="docs/media/jeste_trailer.mp4">open it on GitHub</a> or <a href="https://github.com/nearbycoder/Jeste/raw/main/docs/media/jeste_trailer.mp4">download it</a>. Every frame is the real game, played by the project's automated solver.</sub>
</p>

## About

Mira Vale grew up as a jester in the travelling *Lark & Lantern* troupe, trained by her
grandmother **Nana Odile**, the greatest clown who ever lived. Nana always promised they
would climb **Mount Jeste** together, the mountain whose wind is said to laugh.

Nana died last winter. Mira never cried. She kept smiling and performing, until one night
on stage she froze, dropped every ball, and the crowd laughed *at* her. So she goes to climb
Jeste alone. The old bell-ringer at the foot of the mountain has a warning for her:

> *"Jeste's a trickster. They say it shows you whatever you hide behind your smile."*

Jeste is a tight, forgiving climb in the tradition of modern precision platformers. It runs
on an eight-way dash and runs through nine chapters, each built around one new idea. Deaths
cost about a second. The challenge is optional, the secrets are worth it, and an assist mode
is always one menu away.

## How to play

| Action | Keyboard (rebindable) | Gamepad |
|---|---|---|
| Move / aim | Arrow keys or WASD | D-pad or left stick |
| Jump | C, Space or J | A |
| Dash (8 directions) | X, K or Shift | X or B |
| Grab / climb | Z, V or L | Shoulders or triggers |
| Pause | Esc, Enter or P | Start |

- **Hold jump** to jump higher. **Jump off a wall** to kick away from it.
- **Hold grab** against a wall to cling and climb. Climbing drains stamina, which refills on the ground.
- **Dash** once in the air in any of eight directions. Mira's cap shows when the dash is ready (red), spent (blue) or doubled (pink). Landing recharges it.
- Menus repeat when you hold a direction (keys, D-pad or stick).
- **F11 or Alt+Enter** switches between fullscreen and a window anywhere in the game (F11
  only if you haven't bound it to an action).
- **The mouse works in every menu**: point at a row to select it, left-click to choose it,
  right-click to go back. On chapter select, click a chapter's marker on the trail (or an arrow)
  and then the card; in the checkpoint picker, click a room's pip or the postcard's arrows.
  A click on a volume slider sets it there, a click in Controls starts a rebind (right-click
  cancels it), and a click reads the next line of a cutscene. *Erase Save* only erases on a
  click on its *Erase* prompt. The **mouse wheel** steps through chapters and checkpoints,
  changes a volume slider or a setting like Window Size under the pointer, moves the selection
  in other lists, and scrolls the credits (which also take a click).
- **Hold Pause** (Esc or Start) during a cutscene to skip the rest of it. Tapping jump or dash still advances line by line.
- **Start from any checkpoint.** Once you've reached more than one room of a chapter, choosing
  it on the map lets you pick where to start with Left/Right: *Continue*, the start, or any
  room you've reached (secret rooms aren't listed). The postcard shows that room, the text beside it shows
  which of its berries and bell you still lack, and a red dot over a room's pip means something
  there is still missing. Only runs from the chapter's start can set a Best time.
- **Pause → Restart Chapter** (after a confirm) starts a fresh run from the chapter's first
  room, for golden-berry attempts and speedruns. The pause screen also shows the chapter's berries.
- **Options → Controls** (on the title screen or in the pause menu) rebinds every key, and Jump, Dash and Grab also take a pad button, swapping on conflicts. On-screen prompts follow whichever device you used last, name keys the way your keyboard layout prints them (keys are bound by position, so on a French AZERTY keyboard the default Grab key reads W and WASD reads ZQSD), and name pad buttons the way your controller does (A / Cross / B for jump on Xbox, PlayStation and Nintendo pads).
- **Options → Controls → Grab Mode: Toggle** makes one press of grab hold on until the next press, so you don't have to keep the button down while climbing. Dying lets go; moving to the next room doesn't.
- **Options → Smooth Motion** draws movement between the game's 60 Hz steps. *Auto* (the default) turns it on when your display's refresh rate isn't a multiple of 60 Hz (144, 165, 75 Hz…) or Game Speed is below 100%, and leaves it off otherwise, since it adds up to one step (17 ms) of display delay.
- **Options → Reduce Flashing** dims full-screen flashes (bells, deaths, cutscenes, mask swaps) and the dash shimmer to a fifth of their strength. **Screen Shake** can be turned off separately.
- **Pause → Assist** offers slower game speed (50–100%, which slows the whole game, controls included), infinite stamina,
  **Air Dashes** (*Two* gives two dashes wherever a room gives one; *Infinite* never spends one;
  rooms before Mira learns to dash stay dashless) and invincibility. Your progress counts the same.
- **Unplugging a controller** (or a pad's battery dying) pauses the game, as does switching to
  another window. The mouse cursor hides while you play and comes back when you move the mouse.
- **Pause → Assist → Route Ghost** shows a translucent Mira running the room the way the
  automated solver proved it can be done, using only the moves the game teaches. She loops,
  restarts with you when you respawn, and changes nothing. She runs in a simulation of her
  own, so her gondolas, crumbling boards, gates, mask blocks, Grin, and the berries, bells and
  keys she picks up are drawn in her tint wherever they differ from yours, and where she passes through one of your blocks (a wall she
  has broken, a gate she has opened) it's outlined in her tint. A strip at the bottom left lights up the buttons she's
  pressing, named by your own bindings. After 10 deaths in a room the game points you to
  her, once. Set her to **Berries** and she shows how to take every berry and bell in the
  room while you're still missing one, then the way into a secret room that still holds
  something, then the exit (a tab above her buttons says which).

## Features

### Movement that feels right

<img src="docs/media/screenshot_dash.png" alt="Mira chains a dash through three green dash gems over a spike pit in Lantern Town" width="100%">

A deterministic 60 Hz simulation with coyote time, jump buffering, variable jump height,
half-gravity at the apex, wall slides, wall jumps, stamina climbing, climb-hops and
8-way dashes. Under that sit the advanced techniques: **supers, hypers, wavedashes and
wall-bounces**, plus dash corner correction and momentum lift-boosts from moving platforms.

### Nine chapters, one new idea each

<img src="docs/media/screenshot_curtains.png" alt="Mira glides through red velvet curtains on the Hollow Stage, a dream theatre inside the mountain" width="100%">

| | Chapter | New mechanic |
|---|---|---|
| Prologue | **The Foot of Jeste** | Run, jump, climb, wall-jump, and finally the dash |
| 1 | **Lantern Town** | Jack-in-the-box springs, crumbling boards, dash gems |
| 2 | **The Hollow Stage** | Velvet curtains you dash through, and a chase |
| 3 | **The Grand Carnival** | Keys and gates, comedy/tragedy mask blocks that swap on every dash, cracked walls |
| 4 | **Whistling Ridge** | Gusting wind (walls shelter you) and cable gondolas |
| 5 | **Mirror Cathedral** | Circus balloons that catch and launch you, mirror panes |
| 6 | **Undertow** | Pinball bumpers, twin gems (two dashes), another chase |
| 7 | **The Summit** | Two dashes and every mechanic, remixed |
| Epilogue | **The Show** | A curtain call |

### The chase

<img src="docs/media/screenshot_chase.png" alt="The Grin, Mira's mirror-image, chases her through the Hollow Stage, replaying her every move" width="100%">

In chase rooms, **the Grin** (Mira's own reflection) follows a fraction of a second
behind, replaying every move you made. Stop to think and it catches you.

### Collectibles and secrets

- **61 Sunberries**, including 4 **winged** ones that fly away the moment you dash.
- **7 Jester Bells**: Nana's lost bells, hidden in secret rooms behind fake and cracked walls. Each one comes with a message.
- **7 Golden Sunberries**: grab one at the start of a chapter and carry it to the end without dying.

### A story with heart

<img src="docs/media/screenshot_story.png" alt="Old Bellamy warns Mira that Jeste is a trickster in a cutscene with animated portraits" width="100%">

Fully scripted cutscenes with animated, blinking, talking portraits and per-character
voice blips. You meet Old Bellamy the bell-ringer, Tobi the anxious painter, Ringmaster
Oddo (a ghost who never ends his show), and the Grin.

### Juice everywhere

Squash and stretch, dash afterimages and ribbon trails, freeze frames, directional screen
shake, a look-ahead camera, gamepad rumble, and a jester cap with two physics-simulated
tails and jingle bells. The world is painted pixel by pixel from the collision map, with
parallax backdrops, a glow pass, bloom and per-chapter colour grading.

### Front end

A title screen with a campfire and a juggling Mira. Chapter select shows living
postcards rendered from each chapter's real opening room. Results screens show berries,
deaths, time, bells, golden runs and whether the climb set a new Best (or the Best it didn't beat). Options cover volume, fullscreen, window size, smooth motion, screen shake,
reduced flashing, rumble, an optional speedrun timer and key rebinding. The game auto-pauses when the window loses focus,
*Continue* returns you to the last room you entered, and any room you've reached can be a
starting checkpoint.

## Content overview

- **9 chapters** (prologue, seven chapters and an epilogue) with **69 rooms**, 7 of them secret.
- **13 music tracks** built on one recurring theme, plus 7 ambience beds and 36 layered sound effects.
- **6 other speaking characters** besides Mira, each with a portrait and a voice of their own.
- A full clear (every berry, every bell) is short for an expert. The automated route takes under four minutes. Golden runs and blind first climbs take much longer.

## Screenshots

<table>
  <tr>
    <td><img src="docs/media/screenshot_title.png" alt="Title screen: the JESTE logo over Mount Jeste, with Mira juggling by a campfire"></td>
    <td><img src="docs/media/screenshot_chapter_select.png" alt="Chapter select with a living postcard of Whistling Ridge and collectible stats"></td>
  </tr>
  <tr>
    <td><img src="docs/media/screenshot_cathedral.png" alt="Mirror Cathedral: Mira passes through a mirror pane between stained-glass windows"></td>
    <td><img src="docs/media/screenshot_gondola.png" alt="Whistling Ridge: Mira rides a cable gondola across a windy gap"></td>
  </tr>
  <tr>
    <td><img src="docs/media/screenshot_undertow.png" alt="Undertow: glowing pinball bumpers in a dark cave above a spike floor"></td>
    <td><img src="docs/media/screenshot_summit.png" alt="The Summit at 2400 m: Mira dashes out of a velvet curtain above the clouds"></td>
  </tr>
</table>

## Play it

Download **`Jeste-v0.1.0-linux-x86_64.zip`** from the
[latest release](https://github.com/nearbycoder/Jeste/releases/latest), unzip it and run
`./Jeste.x86_64`. It's a single 64-bit binary and needs a Vulkan-capable GPU. Saves and
settings are stored in `~/.local/share/godot/app_userdata/Jeste/`. Each write keeps the
previous copy as `.bak`. If a file is ever damaged (a crash or a full disk mid-write), the
game loads the backup, keeps the damaged file as `.corrupt` and tells you on the title screen.

Windows, macOS and web builds aren't published yet. `export_presets.cfg` has presets for all
three (Windows x86_64, a single-threaded web build, and an ad-hoc-signed, un-notarized
universal macOS app with bundle id `com.nearbycoder.jeste`), but none of them has been
exported or run yet: this machine has only the Linux export template. Treat them as untested
starting points.

## Build from source

**Requirements:** [Godot 4.6+](https://godotengine.org/download) (built and tested with
**4.7.2**) and Python 3. `ffmpeg` is only needed to regenerate audio or the trailer, and
NumPy only to regenerate audio.

```sh
git clone https://github.com/nearbycoder/Jeste.git && cd Jeste
godot --path .                      # play (or open the folder in the Godot editor and press F5)
```

**Run the verification suite.** It needs no display and takes under two minutes with cached solutions (both route sets):

```sh
python3 tests/run_tests.py                      # all chapters: lint, solve, prove, play end-to-end, menu flow
python3 tests/run_tests.py --chapters 1 3 --resolve   # re-solve chosen chapters from scratch
```

Results are written to `tests/REPORT.md`. Every Godot run in the suite gets its own throwaway
`user://` in `build/test_user/`, so tests never read or write your real save or settings.

**Regenerate the assets.** All 56 PNGs and all audio are produced by code. Re-running the art
generator reproduces the committed images byte for byte.

```sh
godot --headless --path . --script res://tools/gen_art.gd    # sprites, tiles, backgrounds, font
python3 -m venv .venv && .venv/bin/pip install numpy
.venv/bin/python tools/gen_audio.py                          # all music, ambience and sfx (needs ffmpeg)
.venv/bin/python tools/gen_audio.py ch3 sfx                  # or just some of them
```

**Export a build.** Install the 4.7.2 export templates first (*Editor → Manage Export Templates*):

```sh
mkdir -p build/linux
godot --headless --path . --export-release "Linux" build/linux/Jeste.x86_64
# untested presets: "Windows Desktop" (build/windows/Jeste.exe), "Web" (build/web/index.html),
# "macOS" (build/macos/Jeste.zip, not notarized, so Gatekeeper will warn)
```

**Rebuild the trailer, teaser, poster and screenshots.** This needs a display, because Godot's Movie Maker renders the footage:

```sh
python3 tools/trailer/make_trailer.py               # all stages; work files go to build/trailer/
python3 tools/trailer/make_trailer.py trailer qc    # re-cut without re-recording
```

**Debug renderers.** These need a display:

```sh
godot --path . --rendering-method mobile res://tools/overview.tscn -- 3 /tmp/ch3.png   # every room of a chapter
godot --path . --rendering-method mobile res://tools/strip.tscn -- 3 3-03 tests/solutions/3_3-03_s0_collect.json /tmp/s.png
godot --path . --rendering-method mobile res://tools/demo.tscn                         # self-playing demo reel
```

**Smooth Motion probe.** Replays a room's Route Ghost route at a forced frame rate and logs
where Mira is drawn each frame (no display needed):

```sh
godot --headless --path . --fixed-fps 144 res://tools/motion_probe.tscn -- 1 1-01 1.0 on build/motion.csv   # chapter room speed on|off out.csv
```

## Project structure

```
scenes/            main (title), chapter select, level, credits
scripts/sim/       deterministic simulation (no nodes): World, RoomDef, LevelDB, Solver
scripts/game/      level controller, renderers, terrain painter, effects, lighting, post-fx,
                   HUD, dialogue, audio, save / settings / input
scripts/ui/        title, chapter select, credits, UI kit, bitmap font renderer
data/levels/       one ASCII level file per chapter (legend below)
data/story/        cutscene scripts
assets/            generated art (PNG) and audio (Ogg / WAV), see tools/
tools/             art + audio generators, debug renderers, demo reel
tools/trailer/     trailer pipeline: shot recorder, cards, caption plates, ffmpeg assembly
tests/             verification suite, cached solver solutions (fastest and basic-moveset), proven routes
docs/media/        trailer, teaser, poster and screenshots used by this README
```

<details>
<summary>Level file legend</summary>

```
#  solid ground        %  alternate solid    ,  background wall   &  fake wall (secret)
=  jump-through        ~  crumbling boards   ^ v < >  spikes
P  spawn point         S [ ]  springs (up / right / left)
*  dash gem            +  twin gem           b  sunberry          w  winged sunberry
H  jester bell         G  golden sunberry    k  key               D  locked gate
C  curtain / mirror    X  cracked wall       R B  comedy / tragedy mask blocks
Z  gondola             z  gondola target     O  balloon           o  bumper
E  chapter end         N  NPC                1-9 cutscene trigger zones
f l c t s x j a u m q r   decorations
```

Room headers set `exits` (e.g. `right:1-02 top[3-8]:1-03b`), `wind`, `dashes`, `chase`,
`npc`, `triggers`, `enter`, `title` and more.
</details>

## Tech highlights

- **One simulation, three users.** `scripts/sim/world.gd` is a node-free, fixed-step
  simulation of a room. The game renders it, the solver searches it and the tests replay it,
  so an input recording that clears a room in a test clears it in the game.
- **Every room is proven beatable.** `scripts/sim/solver.gd` runs a weighted A\* search over
  input macro-actions (run, jump, hold, 8-way dash, climb…). It simulates every candidate
  with the real physics, using a gravity-aware heuristic and TSP-ordered collectibles,
  across parallel headless Godot workers. The suite then proves that every chapter's end is
  reachable and that every collectible can be taken on a route that still finishes. It
  plays each chapter end-to-end through the real `Level` scene with zero deaths, which also
  proves every golden run. It repeats the proofs with the basic moveset only, since the
  solver's fastest routes lean on supers and hypers the game never teaches, and scores each
  room's route for how often a 1-frame timing slip is fatal (`tools/slip_deaths.gd` shows where).
- **Procedural art.** Characters are rigged "paper dolls": hand-drawn ASCII heads and
  torsos with procedurally posed limbs, 34 animation frames each. Terrain is painted per
  pixel from the collision map on worker threads, with bevel, ambient occlusion, material
  detail and snow, grass or crystal caps. Backdrops are layered noise landscapes with set
  pieces.
- **Synthesized audio.** `tools/synth.py` is a small NumPy synthesizer: e-piano, FM bells,
  pads, choir, organ, calliope, drums and a convolution reverb. `tools/gen_audio.py`
  composes 13 tracks on one theme as seamless 32-bar loops, loudness-normalised.
- **Reproducible trailer.** `tools/trailer/` drives the real game through Movie Maker with
  the proven routes, renders captions in the game's pixel font, and assembles everything
  with ffmpeg. That covers transitions on the music grid, a ducked music bed and EBU R128
  loudness.

## Credits and tooling

- **Game, code, art, music and writing:** [nearbycoder](https://github.com/nearbycoder),
  built with [Claude Code](https://claude.com/claude-code) as an AI pair programmer.
- **Engine:** [Godot Engine](https://godotengine.org) 4.7 (MIT).
- **Tools:** Python, NumPy and FFmpeg for audio synthesis and trailer assembly.
- **Movement tuning:** the controller constants follow a player controller published under
  the MIT license. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- **No third-party art, fonts, music or samples.** Every pixel and every sound is generated
  by code in this repository.

## Status and known issues

Jeste **v0.1.0** is a complete, playable game, from the prologue through the epilogue
and credits. It is a first release, so expect rough edges.

- **Linux only** for now. Other platforms should export cleanly but haven't been tested.
- **Gamepad support** (bindings, rebinding, prompts, rumble, analog-stick menu navigation,
  pausing when a pad disconnects) was exercised with simulated input, not on a range of
  physical controllers. Controller families are
  recognised by the name the pad reports, so an unusual pad may show Xbox button names.
- **Difficulty was tuned against a bot.** Every room is proven possible, now also with the
  basic moveset alone (no supers, hypers or wall-bounces, which the game never teaches), and
  the three rooms where small timing slips were most often fatal were eased (2-03, 6-06,
  7-05; the trailer predates these edits). Human-feel playtesting is still light, so some rooms may feel tighter than intended.
  Assist mode is there for that, including the Route Ghost.
- **Fixed on `main`, not yet in a release:**
  - *Game Speed didn't slow gameplay* in v0.1.0. The 50–90% settings only slowed animations and
    timers; Mira moved at full speed. The game now steps its simulation at the chosen speed.
  - *A save could be lost to a crash.* v0.1.0 rewrote the save in place on every room and berry.
    A crash or full disk at that moment left a damaged file, which the next launch silently
    replaced with an empty save. Saves are now written to a temporary file and renamed, with a
    backup. This was checked by damaging files in every way a torn write can, not by pulling the
    power, and the rename path hasn't been run on Windows or the web.
  - *The mouse cursor stayed visible* over the game, in the middle of the screen in fullscreen.
    It now hides while you play.
  - *Rebinding could leave Dash stuck.* Binding the key or pad button that was Dash (X on both
    by default) to Jump left Dash "held" after you let go, so the next level started with a dash
    and your next press of Dash did nothing.
  - *Prompts named the wrong keys on non-US keyboards.* Keys are bound by position, but every
    prompt used the US-QWERTY name, so a French AZERTY player was told "Hold Z to GRAB" when the
    key is printed W. Prompts now follow the keyboard layout. French and German were checked
    under Wayland and X11 (Xwayland), each in a private KWin session; Windows and macOS
    weren't. Letters the pixel font can't draw (Cyrillic, Greek…) fall back to the US name.
- **Route Ghost:** a block that is solid for you but open for her (a wall she has broken, a
  gate she has opened, a mask block that swapped for her) is still drawn as your solid block,
  with an outline in her tint while she is near it. A berry she takes trails her in her tint
  (your own stays where it is), and where you found a berry on an earlier climb, hers is drawn
  over its outline until she takes it. Her dash gems and balloons aren't drawn separately, so
  one she has used still looks ready. None of this has been playtested with a new player.
- **Mouse:** menu hover and clicks were checked with synthetic events (in a real window too),
  not with a physical mouse. There is no mouse wheel support, and gameplay itself is keyboard
  or pad only.
- **Display:** the 320×180 canvas is always integer-scaled, so screens that aren't a multiple
  of it letterbox. *Options → Window Size* picks 2× up to the largest scale that fits, and the
  default (Auto) sizes the window to about three quarters of the screen. Tested on one 4K
  monitor under Wayland. On this machine's X11 (XWayland) session, game windows launched from a
  script started minimised regardless of these settings, so X11 was not checked by eye; in a
  private KWin session's Xwayland, F11 and Alt+Enter switched a real X11 window to fullscreen
  and back.
  *Smooth Motion* was checked by measuring where Mira is drawn on every frame at a forced
  144 fps and at 50% Game Speed, plus captured frames from a real window. Nobody has watched
  it on a real 144 or 165 Hz display yet, and Auto relies on the refresh rate the system reports.
- **No license has been chosen yet.** Until a `LICENSE` file is added, all rights are
  reserved by the author.
