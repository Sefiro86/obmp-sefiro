# Changelog

All notable changes to Sefiro Animation Menu are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

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
