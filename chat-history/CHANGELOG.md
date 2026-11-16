# Changelog

All notable changes to Chat History are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-16

### Added

- Up and Down in the OblivionMP chat browse the lines you sent before, newest first.
- Pressing Down past the newest line brings back the line you were typing.
- History saved on each player's PC (`%LOCALAPPDATA%\Sefiro\ChatHistory\history.txt`): up to 200 lines, no duplicates, kept across game sessions.
- Session-only history when the client mod is missing, so the chat never breaks.
- `Install.ps1` and `Uninstall.ps1` for servers, with a backup of OblivionMP's original chat page and a check that refuses to overwrite a chat page it was not made for.
