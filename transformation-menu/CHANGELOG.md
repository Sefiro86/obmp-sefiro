# Changelog

All notable changes to Sefiro Transformation Menu are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.9.0] - 2026-11-17

First public release (beta).

### Added

- Transformation into 37 game creatures (beasts, undead, daedra, Shivering Isles), with the creature's body, extra
  parts (fur, horns, pouches), animations and attack/hit-reaction montages. The data is generated from the game files.
- Bestiary menu on Alt+U, and the `/transform <id>|off|list` chat command.
- Creature attack damage: while transformed, each hit you deal does the creature's own damage (server side).
- Creature sounds: footsteps, pain, attack, alert and idle.
- Unarmed while transformed: weapon, shield and torch are taken off on the player's own game and given back when
  returning to normal. Weapons and shields are read from the game itself, so items from other mods are covered.
- Character packs (`packs\*.json`): custom humanoid characters as race forms, with skin variants. A pack only shows
  when its `.pak` and plugin are installed; plugin load-order indexes are read from `Plugins.txt`.
- Automatic detection of custom characters without a pack file (new race in a plugin plus its asset in `~mods`).
- Multiplayer: transformations and creature attacks are shown to the other players.
- `Install-Server.ps1`, `Install-Client.ps1` and `Uninstall-Client.ps1`.

### Known issues

- See "Known limitations" in the README: the frame rate may drop with many characters nearby while transformed, a few
  creatures lack melee or combat animations, and torches from other mods are not taken off.
