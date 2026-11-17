# Character packs

A character pack adds a custom humanoid character (a "race" form) to the transformation menu. Each pack is one
`<id>.json` file in this folder. The mod reads the folder when the game starts.

A pack only shows up when what it needs is installed:

- its `.pak` is in `OblivionRemastered\Content\Paks\~mods`;
- its plugin (`.esp`) is listed in `Content\Dev\ObvData\Data\Plugins.txt`.

So a release without a character simply does not list it.

## Format

```json
{
  "format": 1,
  "id": "succubus",
  "name": "Succubus",
  "group": "characters",
  "race": "/Game/Forms/actors/race/ObmpSuccubusRace.ObmpSuccubusRace",
  "requires": { "pak": "0000_ObmpSuccubus_P.pak", "plugin": "ObmpTestNpc.esp" },
  "preload": [ { "plugin": "ObmpTestNpc.esp", "id": "000800" } ],
  "keepVisible": ["succub"],
  "skins": [
    { "id": "default", "name": "Original", "color": "#e2c1b5",
      "albedo": "/Game/.../T_Body_Albedo.T_Body_Albedo", "nnr": "/Game/.../T_Body_NNRS.T_Body_NNRS" }
  ]
}
```

| Field | Meaning |
|---|---|
| `id` | Lowercase letters, digits and `_`, at most 24 characters. The chat command is `/transform pack:<id>`. |
| `name` | Name shown in the menu. |
| `group` | Menu group. `characters` is the default. |
| `race` | Unreal path of the race asset (`TESRace`) whose body the player takes. |
| `requires.pak`, `requires.plugin` | Files that must be installed for the pack to appear. |
| `preload` | NPC forms that use the race. The game loads the race through them. Give the plugin file and the record id inside that plugin (6 hex digits). The load-order index is read from `Plugins.txt`, so it works in any load order. |
| `keepVisible` | Words in component or mesh names that must never be hidden (parts of your own character). |
| `skins` | Optional texture variants. The first one is the default. `albedo` and `nnr` are the textures written into the game skin parameters "BaseColor Map" and "NNR Map". They must already be in memory, for example referenced by the body material. `color` is the swatch shown in the menu (any CSS colour or gradient). |

Skin `<skin>` of a pack is used with `/transform pack:<id>:<skin>` (the first skin is plain `pack:<id>`).

## Body mesh requirement

The body mesh of the race must have **Allow CPU Access** turned on for LOD0 (`bAllowCPUAccess` in the mesh's LOD
settings), like the game's own bodies. The game rebuilds the character's merged mesh whenever the race or the
equipment changes, and it reads the vertices of the body from CPU memory. Without the flag the engine frees that copy
after the first build, and the next rebuild crashes the game: typically when you return to normal, or switch to
another form, after the custom character has been on screen for a while.
