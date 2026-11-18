# Changelog

All notable changes to the Spriggan character pack are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-18

First public release.

### Added

- Playable Spriggan for Sefiro Transformation Menu 0.9.1: 3D model by Seakas, 4K textures, game humanoid skeleton.
- IK Rig setup: the Spriggan copies the pose of a hidden human body animated by the game, with IK on hands and feet.
- Sheathed weapons on the Spriggan's back and hip (mesh sockets on the race's body, no post-process).
- Dedicated plugin `ObmpSpriggan.esp` and pack file `spriggan.json`, with its SyncMap entries.
- `Install-Client.ps1` (finds the game through Steam, or `-GamePath`) and `Uninstall-Client.ps1`.
