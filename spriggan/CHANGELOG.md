# Changelog

All notable changes to the Spriggan character pack are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-11-18

### Added

- `Install-Server.ps1`: installs the Spriggan once, in the server's `modloader`, and the ReadyM launcher copies it to
  every player before the game starts. It adds `ObmpSpriggan.esp` to the modloader's `Plugins.txt`, creating that file
  from the game's load order when it does not exist yet (`-GamePath` if the game is not found through Steam).
- `Uninstall-Server.ps1`: removes those files and the plugin line.
- The server installer refuses, before changing anything, a release that contains an empty file: the ReadyM launcher
  cannot send empty files to players, and the game would not launch.

### Changed

- The release folder uses the `DogmaModInstaller` package layout: `dogma-package.json`, `Paks\~mods\`, `Data\` and
  `client-appdata\Mods\SefiroTransformation\packs\` (it was `game\` and `packs\`), so it can be installed with that
  tool too.
- `Install-Client.ps1` is now only needed on servers without a `modloader` folder.

No change to the character.

## [1.0.0] - 2026-11-18

First public release.

### Added

- Playable Spriggan for Sefiro Transformation Menu 0.9.1: 3D model by Seakas, 4K textures, game humanoid skeleton.
- IK Rig setup: the Spriggan copies the pose of a hidden human body animated by the game, with IK on hands and feet.
- Sheathed weapons on the Spriggan's back and hip (mesh sockets on the race's body, no post-process).
- Dedicated plugin `ObmpSpriggan.esp` and pack file `spriggan.json`, with its SyncMap entries.
- `Install-Client.ps1` (finds the game through Steam, or `-GamePath`) and `Uninstall-Client.ps1`.
