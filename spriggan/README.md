# Spriggan

A playable Spriggan for OblivionMP: a character pack for [Sefiro Transformation Menu](../transformation-menu). Pick it
in the menu and your character becomes a Spriggan, with every animation of the game, weapons in its hands and on its
back, and the other players seeing it too.

**Version 1.0.0.** 3D model by **Seakas**, thank you!

## Features

- A full-size Spriggan (about 1.94 m) with 4K textures, on the game's humanoid skeleton.
- **Every game animation**: walk, run, sneak, swim, combat, spells, idles. The game animates a hidden human body and
  the Spriggan copies its pose through an IK Retargeter, so it keeps its own proportions.
- **Hands on the weapon, feet on the ground**: IK goals pin the hands to the weapon grip and the feet to where the
  game puts them, on slopes and while sneaking too.
- **Weapons on its body**: sheathed weapons sit on the Spriggan's back and hip, not inside it.
- **Inventory preview**: the 3D character in the inventory (I) is a Spriggan too.
- **Multiplayer**: the other players with the pack see you as a Spriggan.

## Requirements

- [Sefiro Transformation Menu](../transformation-menu) **0.9.2 or later** on the server (0.9.1 works too, if every
  player installed its Lua mods by hand).
- Oblivion Remastered started through the ReadyM launcher.

## Install

The server owner installs the Spriggan once, on the server. Players install nothing: the ReadyM launcher gives it to
them when they join.

1. Install or update Sefiro Transformation Menu on the server, following its guide.
2. Stop the server.
3. From the release folder, run in PowerShell:
   ```powershell
   .\Install-Server.ps1 -ServerPath "D:\OblivionMP\Server"
   ```
4. Start the server.

The script copies into the server's `modloader` folder:

| File | Copied to | On each player's PC |
|---|---|---|
| `Paks\~mods\0000_ObmpSpriggan_P.pak`, `.ucas`, `.utoc` | `modloader\@GAME\Content\Paks\~mods` | `OblivionRemastered\Content\Paks\~mods` |
| `Data\ObmpSpriggan.esp` | `modloader\@GAME\Content\Dev\ObvData\Data`, and adds it to that folder's `Plugins.txt` | `OblivionRemastered\Content\Dev\ObvData\Data` |
| `client-appdata\Mods\SefiroTransformation\packs\spriggan.json` | `modloader\@APPDATA\Mods\SefiroTransformation\packs` | `%APPDATA%\ReadyM.Launcher\Oblivion\Mods\SefiroTransformation\packs` |

**About `Plugins.txt`:** the `Plugins.txt` in the server's modloader replaces the one of every player who joins, so
everyone has the server's load order. If the modloader has none yet, the script creates it from the `Plugins.txt` of
the game on the server PC (found through Steam; otherwise pass `-GamePath "D:\Games\Oblivion Remastered"`), then adds
`ObmpSpriggan.esp` at the end. Plugins already listed keep their order.

**With DogmaModInstaller:** the release folder has the layout the group's `DogmaModInstaller` reads
(`dogma-package.json`, `Paks\`, `Data\`, `client-appdata\`), so you can also install it with that tool: select the
extracted `Sefiro.Spriggan-<version>` folder, and pass `-Game` so that it can create `Plugins.txt` from the game's
load order. Use one tool or the other for this pack, not both.

**Servers without a `modloader` folder:** each player who should see the Spriggan runs `.\Install-Client.ps1` from
the release folder, with the game closed and the Transformation Menu Lua mods installed. It copies the same files into
the game and `%APPDATA%` (it finds the game through Steam, or pass `-GamePath`) and adds the plugin to `Plugins.txt`.

If PowerShell refuses to run the scripts, start it with `powershell -ExecutionPolicy Bypass` or right-click the
script and choose **Run with PowerShell**.

To check that it works, look in the game's `UE4SS.log` for `[SefiroTransformationSync] spriggan: ... ObmpSprigganRace`
and `[SefiroTransformation] pack spriggan: 1 skins`.

## Use

- **Alt+U** opens the transformation menu: the Spriggan is under **Characters**. "Back to normal" is at the bottom.
- **Chat:** `/transform pack:spriggan`, and `/transform off` to go back.

## Known limitations

- Player transformation only: there is no Spriggan NPC in the world.
- When you stop walking, the feet make a small step before the idle pose. It is the game's own stop animation, which
  the Spriggan copies (you can see it on the human body with Shift+F9).
- Players without the pack see your normal character.

## Uninstall

Ask players to turn back to normal first.

- **Server:** stop it and run `.\Uninstall-Server.ps1 -ServerPath "D:\OblivionMP\Server"` from the release folder. It
  removes the pak, the plugin (and its line in the modloader's `Plugins.txt`) and the pack file from the modloader.
  Start the server again.
- **Player's PC** (optional): close the game and run `.\Uninstall-Client.ps1`. It removes the pak, the plugin (and its
  line in `Plugins.txt`) and the pack file.

## How it was made

- The model was rebound in Blender to the game's humanoid skeleton (bone axes and names of the game), scaled to the
  game's pelvis height, and imported in Unreal Engine 5.3 on `SKEL_HumanoidSkeleton`.
- The race's body is a copy of the game's human body (`SK_Spriggan_Source`), with mesh sockets that move the weapon
  anchors to the Spriggan's back and hip. The Spriggan mesh has a post-process AnimBlueprint with Retarget Pose From
  Mesh and an IK Retargeter (36 chains, Limb solvers on the hands and feet).
- The plugin `ObmpSpriggan.esp` holds the race and an NPC form that loads it; `spriggan.json` lists them for the
  game's form map.

## Credits and license

- **3D model: Seakas.** The model and its textures are not covered by the MIT license of this repository: do not
  reuse them outside this pack without Seakas's permission.
- Pack, scripts and setup: Sefiro. Scripts are MIT, see [LICENSE](../LICENSE).

OblivionMP is made by ReadyM. The Elder Scrolls IV: Oblivion Remastered is made by Bethesda Game Studios and Virtuos.
This project is not affiliated with or endorsed by ReadyM or Bethesda.
