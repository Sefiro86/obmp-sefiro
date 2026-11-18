# Sefiro Transformation Menu

Turn into one of the game's creatures, or into a custom character, in OblivionMP. You keep your own controls, stats,
inventory and spells, while the creature brings its body, animations, sounds and attack damage. The other players
see the creature too.

**Version 0.9.1 (beta).** Most creatures have been tested in game; see [Known limitations](#known-limitations).

## Features

- **37 creatures** in four groups, read from the game's own data:
  - Beasts of Tamriel: Troll, Ogre, Minotaur, Spriggan, Mountain Lion, Wolf, Bear, Boar, Deer, Dog, Rat, Sheep,
    Mud Crab, Goblin, Land Dreugh, Scalon, Imp.
  - Undead: Skeleton, Zombie, Ghost, Wraith, Lich.
  - Daedra: Xivilai, Daedroth, Clannfear, Scamp, Flame Atronach, Frost Atronach, Storm Atronach, Spider Daedra.
  - Shivering Isles: Baliwog, Elytra, Gnarl, Grummite, Hunger, Shambles, Flesh Atronach.
- **A bestiary menu** (Alt+U), or the `/transform` chat command.
- **The creature's attack damage**: the server sets the damage of every hit you deal while transformed to the
  creature's own value, whatever weapon your character holds.
- **The creature's sounds**: footsteps, pain, attack, alert and idle sounds.
- **Unarmed while transformed**: your weapon, shield or torch is taken off when you transform and given back when you
  return to normal. Creatures have no animations for weapons in hand.
- **Character packs**: custom humanoid characters (a new race with its own body) show up in the menu, with optional
  skin variants. Characters installed without a pack file are **detected automatically**.
- **IK Rig characters**: a pack can bring a character with its own proportions. The game animates a hidden human
  body, which holds the weapons; the character copies its pose through an IK Retargeter, with hands on the weapon and
  feet on the ground.
- **Inventory preview**: the 3D character in the inventory (I) shows your transformation too.
- **Multiplayer**: everyone with the mod sees your transformation and your creature's attacks.
- **Light on the server**: the server only keeps who is transformed into what and adjusts the damage of hits.

## Requirements

- An OblivionMP 1.1.0 server with the **OblivionMP.Chat** mod (it ships with OblivionMP).
- On each player's PC: Oblivion Remastered started through the ReadyM launcher, which includes UE4SS.

## Install

The server owner installs everything once, on the server. Players install nothing: the ReadyM launcher gives them
the mod when they join.

1. Stop the server.
2. From the release folder, run in PowerShell:
   ```powershell
   .\Install-Server.ps1 -ServerPath "D:\OblivionMP\Server"
   ```
3. Start the server.

The script puts the two parts of the mod in the server folder:

| Part | Copied to | How it reaches the players |
|---|---|---|
| The OblivionMP mod (`mods\Sefiro.TransformationMenu`) | `<server>\mods` | The server sends its client half when a player connects. An existing `server\config.json` is kept. |
| The UE4SS Lua mods `SefiroTransformation` and `SefiroTransformationSync` (`client-appdata\Mods`) | `<server>\modloader\@APPDATA\Mods` | The launcher copies them to `%APPDATA%\ReadyM.Launcher\Oblivion\Mods` before the game starts. |

`SefiroTransformationSync` registers the forms of the installed character packs with the game (see
[Character packs](#character-packs)); it does nothing when no pack needs it.

Run `Install-Server.ps1` again after each update, with the server stopped.

**With DogmaModInstaller:** the release folder has the layout the group's `DogmaModInstaller` reads
(`dogma-package.json`, `mods\`, `client-appdata\`), so you can also install it with that tool: select the extracted
`Sefiro.TransformationMenu-<version>` folder and keep **Keep server\config.json when updating** checked
(`-PreserveConfig` on the command line). Use one tool or the other for this mod, not both.

**Servers without a `modloader` folder** (or with `-SkipModloader`): only the OblivionMP mod is installed, and each
player runs `.\Install-Client.ps1` from the release folder with the game closed. It copies the two Lua mods into
`%APPDATA%\ReadyM.Launcher\Oblivion\Mods` and enables them in `mods.txt`.

If PowerShell refuses to run the scripts, start it with `powershell -ExecutionPolicy Bypass` or right-click the
script and choose **Run with PowerShell**.

To check that it works, look in the game's `UE4SS.log` (in `...\Oblivion Remastered\OblivionRemastered\Binaries\Win64`)
for lines starting with `[SefiroTransformation]`, for example `37 creatures from the data file`.

## Use

- **Alt+U** opens the menu. ↑/↓ (or W/S) select, ←/→ (or A/D) change a character's skin, **Enter** transforms,
  **Esc** closes. "Back to normal" is at the bottom.
- **Chat:** `/transform <id>`, `/transform off`, `/transform list`. Creature ids are lowercase names without spaces:
  `troll`, `mountainlion`, `flameatronach`, `spiderdaedra`... Character packs use `pack:<id>` and
  `pack:<id>:<skin>`.
- **Shift+F3** turns the diagnostic lines in `UE4SS.log` on and off.
- **Shift+F9** (IK Rig characters, only on your screen) cycles: normal, the hidden human body alone, both bodies.
  Useful to tell whether a pose comes from the game's animation or from the character.

### Who can transform

`mods\Sefiro.TransformationMenu\server\config.json` on the server:

```json
{
  "allowedAccounts": []
}
```

An empty list lets everyone transform. Put ReadyM account ids (GUIDs) in the list to allow only those players.

## Character packs

A character pack adds a custom humanoid character. It is a `<id>.json` file in
`%APPDATA%\ReadyM.Launcher\Oblivion\Mods\SefiroTransformation\packs`. It names the character's race, the files it
needs and its skin variants. The format is described in [`lua/SefiroTransformation/packs/README.md`](lua/SefiroTransformation/packs/README.md).

A pack only appears when its `.pak` is in `Content\Paks\~mods` and its plugin is in `Plugins.txt`. A character
whose race and Unreal asset are installed, but which has no pack file, appears under **Detected characters** with its
default look.

A pack can list its plugin forms in `syncMap`: `SefiroTransformationSync` then adds them to the game's form map at
startup, so the character needs no other Lua mod. Load-order indexes are read from `Plugins.txt`, including the
Deluxe rule (without the Deluxe edition, plugins after `AltarDeluxe.esp` move down by one).

Every player who should see a custom character needs its files. Install character packs on the server too, in its
`modloader` (the Spriggan's `Install-Server.ps1` does this), so that the launcher gives them to every player.

## Known limitations

- **Beta:** not every creature has been tested in every situation. Please report problems.
- While you are a creature, the game updates all animations on its main thread (`a.ParallelAnimUpdate 0`) and sets it
  back when you return to normal. Without this, OblivionMP 1.1.0 can freeze when an animation calls into the
  transformed player from a worker thread. With many characters nearby you may notice a lower frame rate.
- Ghost and Lich have no melee attack animation; they attack with the game's normal attack.
- Bear, Sheep, Ghost and Lich have no "ready for combat" animations: after 1.5 s without attacking they put the
  hands down again.
- Torches added by other mods are not taken off. Weapons and shields of any mod are.
- If you disconnect while transformed, you come back with your weapon and shield unequipped (they are in your
  inventory).
- Not included: horse, Mehrunes Dagon, Jyggalag, Gatekeeper (oversized or special), will-o'-the-wisp and slaughterfish.

## Uninstall

- **Server:** stop it and run `.\Uninstall-Server.ps1 -ServerPath "D:\OblivionMP\Server"` from the release folder. It
  deletes `mods\Sefiro.TransformationMenu` (with `server\config.json`: copy it first to keep it) and the Lua mod files
  in `modloader\@APPDATA\Mods`. Character packs installed by other releases stay. Start the server again.
- **Player's PC** (optional, the Lua mods do nothing without the server mod): close the game and run
  `.\Uninstall-Client.ps1`, or delete
  `%APPDATA%\ReadyM.Launcher\Oblivion\Mods\SefiroTransformation` and `...\SefiroTransformationSync` and their lines
  in `mods.txt`.

## Building from source

- `build.ps1` builds the mod with the .NET 10 SDK and writes the release folder and zip to `dist`.
- `native\` is the source of `SefiroTransformation_native.native`, the small native core that runs `unequipitem` and
  `equipitem` on the game's thread (`build.bat`, MSVC x64).
- `tools\creature_inventory.py` regenerates the creature data (`creatures_data.lua`, `CreatureCatalog.g.cs`,
  `HandItems.g.cs`) from the game files. It needs a local copy of the game and the `obrassets` asset reader, which is
  not part of this repository.

## License

MIT, see [LICENSE](../LICENSE). OblivionMP is made by ReadyM. The Elder Scrolls IV: Oblivion Remastered is made by
Bethesda Game Studios and Virtuos. This project is not affiliated with or endorsed by ReadyM or Bethesda.
