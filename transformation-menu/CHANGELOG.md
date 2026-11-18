# Changelog

All notable changes to Sefiro Transformation Menu are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.9.1] - 2026-11-18

### Added

- IK Rig character packs (`retargetMesh`): the game animates a hidden human body, which holds the weapons, and the
  character copies its pose through an IK Retargeter, with the hands on the weapon and the feet on the ground. A
  character can keep its own proportions and still use every animation and weapon of the game.
- `SefiroTransformationSync`, a second small Lua mod: it adds the forms listed in a pack's `syncMap` to the game's
  form map, so a character pack needs no other Lua mod. `Install-Client.ps1` and `Uninstall-Client.ps1` handle it.
- The 3D character in the inventory (I) shows your transformation into a character pack.
- Shift+F9 (IK Rig characters, your own screen only): normal / human body alone / both bodies, to tell whether a pose
  comes from the game's animation or from the character.

### Fixed

- Crash when the race changed twice in a row: switching from one character to another, changing skin, or opening the
  pause menu while the game was re-applying the race. Race changes are now at least 1.5 s apart, and a switch from a
  character to another changes the race only once.
- "Back to normal" did nothing after some time as a character: the game had unloaded your original race. It is now
  kept loaded until you return to normal.
- On the Standard edition, characters from a plugin listed after `AltarDeluxe.esp` did not load (wrong load-order
  index). The index now follows the game's rule.
- A character could be applied before its race had finished loading.

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
