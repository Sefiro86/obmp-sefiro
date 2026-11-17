# Sefiro Animation Menu

An animation test bench on your own character in OblivionMP. Open the menu, pick any animation of the game and watch
your character play it, framed by a bench camera, in slow motion, frame by frame or in a loop.

**Version 0.9.2 (beta).** Tested in game on a human character; see [Known limitations](#known-limitations).

## Features

- **Every animation for your body**: the menu reads your character's skeleton and lists the animations made for it.
  As a human you get the 759 third-person humanoid animations of the game; while transformed into a creature (for
  example with [Transformation Menu](../transformation-menu)) you get that creature's animations instead.
- **Loaded on demand**: animations the game has not loaded yet are listed in italics as "not loaded" and are loaded
  when you play them.
- **Bench camera**: a fixed camera on the spot where you opened the menu, with six framings (three-quarter, front,
  profile, back, close-up, feet), orbit, height, zoom and a slow turntable. Mouse or keyboard.
- **Playback controls**: speed from 0.1× to 2×, pause, one frame back or forward, loop, an A-B section to repeat,
  a clickable timeline, and a tour that plays every animation from the selection down.
- **Root motion on or off**: let the animation move your character, or keep it in place.
- **Back to the start (F7)**: after animations that move you, go back to where you were when you opened the menu.
- **Favorites and recent animations**, and search by name.
- **Your game is given back when you close the menu**: the animation stops, your controls come back, and the game
  camera returns to the state it had when you opened the menu.

## Requirements

- An OblivionMP 1.1.0 server.
- On each player's PC: Oblivion Remastered started through the ReadyM launcher, which includes UE4SS.

## Install

The mod has two parts:

1. **Server** (once, by the server owner): the OblivionMP mod. The server sends its client half to every player.
   - Stop the server.
   - From the release folder, run in PowerShell:
     ```powershell
     .\Install-Server.ps1 -ServerPath "D:\OblivionMP\Server"
     ```
     or copy `mods\Sefiro.AnimationMenu` into the server's `mods` folder by hand.
   - Start the server.
2. **Each player's PC**: the UE4SS Lua mod that plays the animations and drives the camera.
   - Close the game.
   - Run `.\Install-Client.ps1` from the release folder. It copies `lua\SefiroAnimationMenu` into
     `%APPDATA%\ReadyM.Launcher\Oblivion\Mods` and enables it in `mods.txt`.

If PowerShell refuses to run the scripts, start it with `powershell -ExecutionPolicy Bypass` or right-click the
script and choose **Run with PowerShell**.

To check that it works, open `%APPDATA%\ReadyM.Launcher\Oblivion\Mods\SefiroAnimationMenu\animtest.log`: after the
game starts it shows a line like `catalog: 2564 animations`.

## Use

Switch to third person, then press **Alt+Y** to open or close the menu. While it is open the game's mouse cursor is
on and your character stands still.

| Key | Action |
|---|---|
| ← → | change tab (Movement, Combat, Poses, Falls, Favorites, Recent) |
| ↑ ↓, Page Up, Page Down | select an animation; double-click a row to play it |
| Enter | play the selected animation |
| Space | pause and resume |
| + − | speed |
| , . | one frame back or forward |
| [ ] \ | mark the start and the end of a section to repeat, clear it |
| F1 | loop |
| F2 | stop |
| F7 | go back to where you were when you opened the menu |
| F8 | tour from the selection down |
| M | root motion on or off |
| * | add to or remove from favorites |
| Ctrl+F or / | search by name (Esc leaves the search box) |
| 1 … 6 | camera framings |
| A D, W S, Q E (hold) | orbit, raise and lower, zoom |
| R, T | reset the framing on your current spot, slow turntable |
| ? | all controls |
| Esc or Alt+Y | close the menu |

**How animations play.** Every animation plays through your character's animation blueprint, as the game would play
it: montages (names starting with `AM_`) directly, sequences on the blueprint's full-body slot. The menu never takes
your character out of its animation blueprint, because OblivionMP reads the animation values it sends to the other
players from it on every frame.

## Known limitations

- **Only you see the animations.** The other players see your character standing still.
- **Creature bodies are less tested than humans.** The creature list depends on reading the skeleton of your current
  body; if it cannot be read, the menu falls back to the humanoid list and says so in `animtest.log`. Sequences play on
  the `FullBody` slot: a creature animation blueprint without that slot shows montages only.
- **Context animations** (beds, chairs, mounting a horse, tools) carry game events meant for real furniture and
  horses. Played on their own they can change the state of the game camera; the menu puts it back when you close it.
  If your view still looks wrong after closing, sit on a real chair and stand up.
- **The catalog matches the game version of November 2026.** After a game update, regenerate it with
  `tools\make_catalog.ps1` (needs [retoc](https://github.com/trumank/retoc)). Animations missing from the catalog
  still show up once the game has loaded them.

## How it works

- `src\` is the OblivionMP C# mod: the Alt+Y key, the menu page (`web\index.html`) and the file exchange with the
  Lua mod. Commands go to `cmd.txt`; the Lua answers with `list.txt` (animations and state) and `pos.txt` (timeline).
- `lua\SefiroAnimationMenu\` is the UE4SS Lua mod. All work runs in the local player's tick on the game thread:
  playing animations (montages, and sequences as dynamic montages on the `FullBody` slot), the bench
  camera (a `CameraActor` set as the view target), input and cursor, and loading animations with the engine's own
  loader (`KismetSystemLibrary.LoadAsset_Blocking`).
- `catalog.txt` lists every third-person animation in the game files with its asset path.

## Build

Requires the .NET 10 SDK.

```powershell
.\build.ps1
```

The release folder and zip are written to `dist\`.

## License

MIT, see [LICENSE](../LICENSE).
