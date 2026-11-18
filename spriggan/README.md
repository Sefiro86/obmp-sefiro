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

- [Sefiro Transformation Menu](../transformation-menu) **0.9.1 or later**, on the server and on each player's PC.
- Oblivion Remastered started through the ReadyM launcher.

## Install

On **each player's PC** that should see the Spriggan:

1. Install or update Sefiro Transformation Menu 0.9.1 (server and client), following its guide.
2. Close the game.
3. From the release folder, run in PowerShell:
   ```powershell
   .\Install-Client.ps1
   ```
   It finds the game through Steam. If it does not, pass the folder that contains `OblivionRemastered`:
   ```powershell
   .\Install-Client.ps1 -GamePath "D:\Games\Oblivion Remastered"
   ```

The script copies:

| File | Where |
|---|---|
| `0000_ObmpSpriggan_P.pak`, `.ucas`, `.utoc` | `OblivionRemastered\Content\Paks\~mods` |
| `ObmpSpriggan.esp` | `OblivionRemastered\Content\Dev\ObvData\Data`, and adds it to `Plugins.txt` |
| `spriggan.json` | `%APPDATA%\ReadyM.Launcher\Oblivion\Mods\SefiroTransformation\packs` |

If PowerShell refuses to run the script, start it with `powershell -ExecutionPolicy Bypass` or right-click the
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

Turn back to normal, close the game and run `.\Uninstall-Client.ps1` from the release folder. It removes the pak, the
plugin (and its line in `Plugins.txt`) and the pack file.

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
