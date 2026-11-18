# Changelog

All notable changes to Sefiro Animation Menu are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.9.3] - 2026-11-18

### Changed

- Players no longer install anything. `Install-Server.ps1` now also copies the Lua mod `SefiroAnimationMenu` into the
  server's `modloader\@APPDATA\Mods`, and the ReadyM launcher copies it to every player before the game starts.
  `-SkipModloader` keeps the old behaviour.
- The release folder uses the `DogmaModInstaller` package layout: `dogma-package.json`, `mods\` and
  `client-appdata\Mods\` (it was `lua\`), so it can be installed with that tool too.
- `Install-Client.ps1` is now only needed on servers without a `modloader` folder.

### Added

- `Uninstall-Server.ps1`: removes the server mod and the Lua mod files from the modloader.
- The server installer refuses, before changing anything, a release that contains an empty file: the ReadyM launcher
  cannot send empty files to players, and the game would not launch.

No change to the mod itself.

## [0.9.2] - 2026-11-17

### Fixed

- Playing a sequence flooded the game's log with about 1,800 `[PARAM SOURCE]` errors per second. Pure mode switched
  the character's mesh out of its animation blueprint, and OblivionMP reads the values it sends to other players
  from that blueprint on every frame. Every animation now plays inside the animation blueprint.

### Removed

- Pure mode (F5) and the rest pose (F9): both needed the character's mesh out of its animation blueprint.

## [0.9.1] - 2026-11-17

First public release (beta).

### Added

- Animation menu on Alt+Y that plays animations on your own character, with keyboard and mouse.
- Animation list chosen from your character's skeleton: humanoid animations as a human, the creature's animations
  while transformed. A catalog of the game's 2564 third-person animations, loaded on demand when played.
- Bench camera with six framings, orbit, height, zoom, turntable and a drag pad.
- Playback: speed, pause, frame step, loop, A-B section, clickable timeline, rest pose, tour.
- Pure mode (the animation alone) and game mode (through the animation blueprint).
- Root motion on or off (M), and F7 to go back to where you were when you opened the menu.
- Favorites, recent animations and search.
- On close, the game camera returns to the state it had when the menu opened.
- `Install-Server.ps1`, `Install-Client.ps1`, `Uninstall-Client.ps1`, and `tools\make_catalog.ps1` to regenerate
  the catalog after a game update.

### Known issues

- Only you see the animations.
- Creature bodies are less tested than humans.
