# obmp-sefiro

Mods and tools by **Sefiro** for OblivionMP, the multiplayer mod for The Elder Scrolls IV: Oblivion Remastered made by ReadyM.

Each project lives in its own folder, with its own guide, changelog and releases.

## Projects

| Project | What it does | Latest release |
|---|---|---|
| [Chat History](chat-history) | Up and Down in the chat bring back the lines you sent before, even after a restart. | [1.0.0](https://github.com/Sefiro86/obmp-sefiro/releases/tag/chat-history-v1.0.0) |
| [Animation Menu](animation-menu) | An animation test bench on your own character: every animation for your body, with a bench camera, slow motion, frame step and loops. | [0.9.3 beta](https://github.com/Sefiro86/obmp-sefiro/releases/tag/animation-menu-v0.9.3) |
| [Transformation Menu](transformation-menu) | Turn into one of 37 game creatures, or into a custom character, with its body, animations, sounds and attack damage. | [0.9.2 beta](https://github.com/Sefiro86/obmp-sefiro/releases/tag/transformation-menu-v0.9.2) |
| [Spriggan](spriggan) | A playable Spriggan character for Transformation Menu, with every game animation, IK hands and feet. 3D model by Seakas. | [1.0.1](https://github.com/Sefiro86/obmp-sefiro/releases/tag/spriggan-v1.0.1) |

## Installing a mod

Download the zip from the [Releases page](https://github.com/Sefiro86/obmp-sefiro/releases) and follow the guide in the project's folder. Releases are tagged by project, for example `chat-history-v1.0.0`.

Every mod is installed once, on the server, with `Install-Server.ps1` (Chat History: `Install.ps1`). Players install nothing: the server sends the OblivionMP mods when they connect, and the ReadyM launcher copies what the server keeps in its `modloader` folder (UE4SS Lua mods, paks, plugins) before the game starts. Transformation Menu, Animation Menu and Spriggan releases also have the folder layout of the `DogmaModInstaller` tool, and an `Install-Client.ps1` for servers without a `modloader` folder.

## Reporting a problem

Open an [issue](https://github.com/Sefiro86/obmp-sefiro/issues) and include:

- the project and version;
- your OblivionMP version;
- what you did, what you expected and what happened;
- the relevant lines of the game's `UE4SS.log` or of the server log.

## License

The code in this repository is released under the [MIT license](LICENSE), unless a project's guide says otherwise for a specific file.

OblivionMP is made by ReadyM. The Elder Scrolls IV: Oblivion Remastered is made by Bethesda Game Studios and Virtuos. This project is not affiliated with or endorsed by ReadyM or Bethesda.
