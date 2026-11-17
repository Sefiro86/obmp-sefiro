# Oblivion Remastered creature census for the transformation (2026-11-17).
# Reads from the paks, with obrassets: Creature* forms -> Blueprint (and its parents) -> body, Reverse AnimBlueprint,
# added parts (fur, horns, bags); then action presets and attack/reaction montages for each AnimBlueprint.
# Writes:
#   data/creatures_inventory.json   everything it found, with the gaps (to decide what to include)
#   lua/SefiroTransformation/Scripts/creatures_data.lua   table for the Lua side (only the creatures in INCLUDE)
#   mod/Sefiro.TransformationMenu.Common/CreatureCatalog.g.cs   names and groups for the C# mod
# Usage: python -I creature_inventory.py
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # with python -I the script folder is not on the path
import esm_creature_damage  # noqa: E402
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ESM = r"E:\SteamLibrary\steamapps\common\Oblivion Remastered\OblivionRemastered\Content\Dev\ObvData\Data\Oblivion.esm"
OBR = os.path.join(ROOT, "..", "tools", "obrassets", "bin", "Release", "net10.0", "obrassets.exe")
CONTENT = "OblivionRemastered/Content/"

# Creatures to offer, per bestiary group (id = name after ABP_Reverse_, lowercase). The excluded ones are noted.
INCLUDE = {
    "beasts": ["troll", "ogre", "minotaur", "spriggan", "mountainlion", "wolf", "bear", "boar", "deer", "dog", "rat",
               "sheep", "mudcrab", "goblin", "landdreugh", "murkdweller", "imp"],
    "undead": ["skeleton", "zombie", "ghost", "wraith", "lich"],
    "daedra": ["xivilai", "daedroth", "clannfear", "scamp", "flameatronach", "frostatronach", "stormatronach",
               "spiderdaedra"],
    "shivering": ["baliwog", "elytra", "gnarl", "grummite", "hunger", "shambles", "fleshatronach"],
}
# Left out of the first release: horse (mount), mehrunesdagon/jyggalag/gatekeeper (giants), willothewisp (no
# ground body), slaughterfish (water only).
GROUP_TITLES = {"beasts": "Beasts of Tamriel", "undead": "Undead", "daedra": "Daedra", "shivering": "Shivering Isles"}
# Displayed name (English, for the release); without an entry the FullName of the chosen form is used.
NAMES = {"troll": "Troll", "ogre": "Ogre", "minotaur": "Minotaur", "spriggan": "Spriggan", "mountainlion": "Mountain Lion",
         "wolf": "Wolf", "bear": "Bear", "boar": "Boar", "deer": "Deer", "dog": "Dog", "rat": "Rat", "sheep": "Sheep",
         "mudcrab": "Mud Crab", "goblin": "Goblin", "landdreugh": "Land Dreugh", "murkdweller": "Scalon", "imp": "Imp",
         "skeleton": "Skeleton", "zombie": "Zombie", "ghost": "Ghost", "wraith": "Wraith", "lich": "Lich",
         "xivilai": "Xivilai", "daedroth": "Daedroth", "clannfear": "Clannfear", "scamp": "Scamp",
         "flameatronach": "Flame Atronach", "frostatronach": "Frost Atronach", "stormatronach": "Storm Atronach",
         "spiderdaedra": "Spider Daedra", "baliwog": "Baliwog", "elytra": "Elytra", "gnarl": "Gnarl",
         "grummite": "Grummite", "hunger": "Hunger", "shambles": "Shambles", "fleshatronach": "Flesh Atronach"}
# Parts the Blueprint does not list as components (the BP code adds them): verified in game.
EXTRA_PARTS = {"xivilai": ["/Game/Art/Creatures/Xivilai/SK_Xivilai_Head.SK_Xivilai_Head"]}
# Preferred BP when several Blueprints use the same AnimBlueprint (the species "base").
PREFER_BP = {"xivilai": "BP_Generic_Xivilai", "minotaur": "BP_Minotaur_01", "skeleton": "BP_Skeleton", "zombie": "BP_Zombie", "dog": "BP_Dog", "wolf": "BP_Wolf", "ghost": "BP_Ghost",
             "goblin": "BP_Goblin", "imp": "BP_Imp"}
# Reach of unarmed attacks (cm): bigger creatures reach further.
REACH = {"troll": 220, "ogre": 220, "minotaur": 220, "daedroth": 220, "xivilai": 170, "clannfear": 170,
         "mountainlion": 170, "spriggan": 150, "scamp": 130, "bear": 200, "landdreugh": 200, "gatekeeper": 300,
         "flameatronach": 160, "frostatronach": 200, "stormatronach": 220, "fleshatronach": 200, "hunger": 170,
         "shambles": 170, "spiderdaedra": 170, "wolf": 150, "dog": 140, "boar": 140, "deer": 140, "sheep": 120,
         "rat": 90, "mudcrab": 100, "baliwog": 130, "elytra": 140, "gnarl": 170, "grummite": 140, "goblin": 130,
         "murkdweller": 140, "imp": 120, "skeleton": 150, "zombie": 150, "ghost": 150, "wraith": 160, "lich": 160}


def obr(*args):
    r = subprocess.run([OBR, *args], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout, r.stderr


def listing(prefix):
    out, _ = obr("list", prefix, "1000000")
    return [l.strip() for l in out.splitlines() if l.strip()]


def json_many(paths, tmp, tag):
    lst = os.path.join(tmp, tag + ".txt")
    d = os.path.join(tmp, tag)
    with open(lst, "w", encoding="utf-8") as f:
        f.write("\n".join(paths))
    _, err = obr("json-many", lst, d)
    print("  " + err.strip().splitlines()[-1])
    res = {}
    for p in paths:
        name = p.split("/")[-1].replace(".uasset", "")
        fp = os.path.join(d, name + ".json")
        if os.path.exists(fp):
            with open(fp, encoding="utf-8") as f:
                res[p] = json.load(f)
    return res


def game_path(obj_path):
    """'/Game/Art/X/SK_A.1' -> '/Game/Art/X/SK_A.SK_A'"""
    base = obj_path.rsplit(".", 1)[0]
    return base + "." + base.split("/")[-1]


def to_content(game):
    return CONTENT + game.split(".")[0][len("/Game/"):]


def main():
    tmp = tempfile.mkdtemp(prefix="crinv_")
    print("1. creature forms")
    # all the forms in the folder (Creature*, but also SE* of Shivering Isles, CG*/DA* of the quests...); Blueprints
    # and interfaces are skipped, the TESCreature type is checked in the JSON
    forms = [p.replace(".uasset", "") for p in listing(CONTENT + "Forms/actors/creature/")
             if p.endswith(".uasset") and not re.search(r"/(BP_|BPC_|BPI_)", p)]
    fj = json_many(forms, tmp, "forms")
    by_bp = defaultdict(list)
    for p, exports in fj.items():
        for e in exports:
            if e.get("Type") == "TESCreature":
                pr = e.get("Properties", {})
                bp = (pr.get("Blueprint") or {}).get("AssetPathName")
                if bp:
                    by_bp[bp.split(".")[0]].append({"form": pr.get("m_formID"), "editorId": pr.get("m_formEditorID"),
                                                     "name": pr.get("FullName"), "scale": pr.get("BaseScale", 1.0)})
    print(f"   {len(fj)} form, {len(by_bp)} Blueprint")

    print("2. Blueprints (and parents)")
    bps, todo = {}, [to_content(b + ".x") for b in by_bp]
    while todo:
        got = json_many(todo, tmp, "bp%d" % len(bps))
        bps.update(got)
        todo = []
        for p, exports in got.items():
            for e in exports:
                if e.get("Type", "").endswith("GeneratedClass") and e.get("Super"):
                    sp = e["Super"].get("ObjectPath", "")
                    if sp.startswith("/Game/"):
                        c = to_content(sp)
                        if c not in bps and c not in todo:
                            todo.append(c)

    def parent_of(p):
        for e in bps.get(p, []):
            if e.get("Type", "").endswith("GeneratedClass") and e.get("Super"):
                sp = e["Super"].get("ObjectPath", "")
                return to_content(sp) if sp.startswith("/Game/") else None
        return None

    def bp_info(p):
        """Body, AnimBlueprint and parts, walking up to the parents for whatever is missing."""
        info = {"body": None, "abp": None, "parts": {}, "presets": None}
        chain = []
        while p and p not in chain:
            chain.append(p)
            p = parent_of(p)
        for q in chain:   # action presets: the first one cited walking up from the child (often it sits in the generic parent)
            m = re.search(r"/Game/Dev/StateMachine/Data/ActionStatePresets/(DT_ActionStatePresets_\w+)", json.dumps(bps.get(q, [])), re.I)
            if m:
                info["presets"] = f"/Game/Dev/StateMachine/Data/ActionStatePresets/{m.group(1)}.{m.group(1)}"
                break
        for p in reversed(chain):   # from parent to child: the child overrides
            for e in bps.get(p, []):
                pr = e.get("Properties", {})
                if e.get("Name") in ("CharacterMesh0", "CharacterMesh0_GEN_VARIABLE"):
                    if pr.get("SkeletalMesh"):
                        info["body"] = game_path(pr["SkeletalMesh"]["ObjectPath"])
                    if pr.get("AnimClass"):
                        info["abp"] = pr["AnimClass"]["ObjectName"].split("'")[1]
                elif "SkeletalMeshComponent" in e.get("Type", "") and "Merged" not in e.get("Type", "") and pr.get("SkeletalMesh"):
                    info["parts"][e["Name"].replace("_GEN_VARIABLE", "")] = game_path(pr["SkeletalMesh"]["ObjectPath"])
        return info

    print("3. action presets and montages")
    presets = {l.split("/")[-1].replace(".uasset", "").replace("DT_ActionStatePresets_", "").lower(): l
               for l in listing(CONTENT + "Dev/StateMachine/Data/ActionStatePresets/DT_ActionStatePresets_") if l.endswith(".uasset")}
    presets.setdefault("slaughterfish", presets.get("slaugtherfish"))
    montages = defaultdict(list)
    # folders with "combat" locomotion (HandToHand/Locomotion): without it, with the weapon drawn the creature's
    # AnimBlueprint has nothing to play and the body stays frozen (bear, 2026-11-17)
    combat_loco = set()
    for l in listing(CONTENT + "Art/Animation/Creatures/"):
        mm = re.match(re.escape(CONTENT) + r"Art/Animation/Creatures/([^/]+)/HandToHand/Locomotion/", l)
        if mm:
            combat_loco.add(mm.group(1).lower())
        m = re.match(re.escape(CONTENT) + r"Art/Animation/Creatures/([^/]+)/.*/(AM_[^/]+)\.uasset$", l)
        if m:
            montages[m.group(1).lower()].append(l)

    def montage_set(key, body):
        dirs = [key]
        if body:   # mesh folder (Art/Creatures/Dog -> dog)
            dirs.append(body.split("/")[-2].lower())
        dirs += {"wolf": ["dog"], "spiderdaedra": ["spiderdaedra"], "landdreugh": ["landdreugh"]}.get(key, [])
        files = []
        for d in dirs:
            if montages.get(d):
                files = montages[d]
                break
        att = [f for f in files if "attack" in f.lower()]
        def pick(pats):
            for pat in pats:
                for f in att:
                    if re.search(pat, f.split("/")[-1], re.I):
                        return f
            return None
        left = pick([r"Left_Power", r"Attack_?Left", r"Attack_?0?1\b", r"Attack_?A\b"])
        right = pick([r"Right_Power", r"Attack_?Right", r"Attack_?0?2\b", r"Attack_?B\b"])
        power = pick([r"Attack_Power\.", r"_Power\.", r"Power"])
        if not left and not right and power:   # only the power attack (sheep, flame atronach): all strikes use it
            left = right = power
        rest = [f for f in att if f not in (left, right, power)]
        left = left or (rest.pop(0) if rest else None)
        right = right or (rest.pop(0) if rest else left)
        power = power or (rest.pop(0) if rest else right)
        rec = [f for f in files if re.search(r"Recoil", f, re.I)]
        stg = [f for f in files if re.search(r"Stagger", f, re.I)]
        g = lambda f: ("/Game/" + f[len(CONTENT):].replace(".uasset", "") + "." + f.split("/")[-1].replace(".uasset", "")) if f else None
        return {"attacks": [g(left), g(right)] if left else [], "power": g(power), "recoil": g(rec[0] if rec else None),
                "stagger": g(stg[0] if stg else None), "montageDir": next((d for d in dirs if montages.get(d)), None)}

    # the creature's Wwise sounds: WwiseAudio/Creature/<Folder>/cre_<x>_<type>; types attack/aware/death/footstep/idle/pain
    sound_dirs = defaultdict(list)
    sound_base = {}
    for l in listing(CONTENT + "WwiseAudio/Creature/"):
        mm = re.match(re.escape(CONTENT) + r"(WwiseAudio/Creature/([^/]+))/([^/]+)\.uasset$", l, re.I)
        if mm:   # in the pak the folder is lowercase "creature": keep the real path (StaticFindObject is case-sensitive)
            sound_dirs[mm.group(2)].append(mm.group(3))
            sound_base[mm.group(2)] = "/Game/WwiseAudio/Creature/" + mm.group(2)   # in the asset imports it is "Creature"
    SOUND_DIR = {"wolf": "SharedDogCreature", "dog": "SharedDogCreature", "xivilai": "SharedXivilaiCreature",
                 "murkdweller": "Scalon"}

    def sounds_of(key):
        d = SOUND_DIR.get(key)
        if not d:
            for cand in sound_dirs:
                if cand.lower().replace("_", "") == key:
                    d = cand
                    break
        if not d:
            return {}
        out = {}
        for t in ("attack", "aware", "death", "footstep", "idle", "pain"):
            names = sorted(n for n in sound_dirs[d] if re.search(r"_" + t + r"s?_?\d*$", n))
            if names:
                out[t] = f"{sound_base[d]}/{names[0]}.{names[0]}"
        return out

    by_abp = defaultdict(list)
    for bp, fl in by_bp.items():
        info = bp_info(to_content(bp + ".x"))
        if not info["abp"] or not info["abp"].startswith("ABP_Reverse_"):
            continue
        key = info["abp"][len("ABP_Reverse_"):-2].lower() if info["abp"].endswith("_C") else info["abp"][len("ABP_Reverse_"):].lower()
        by_abp[key].append({"bp": bp, "forms": fl, **info})

    esm = esm_creature_damage.read(ESM)   # attack damage and health from the CREA records (by formID)
    inv = {}
    for key, cands in sorted(by_abp.items()):
        want = (PREFER_BP.get(key) or "BP_" + key).lower()
        cands.sort(key=lambda c: (c["bp"].split("/")[-1].lower() != want, -len(c["forms"]), len(c["parts"]), c["bp"]))
        c = cands[0]
        f = sorted(c["forms"], key=lambda x: (not (x["editorId"] or "").startswith("Creature"), len(x["editorId"] or "")))[0]
        abp_name = "ABP_Reverse_" + c["abp"][len("ABP_Reverse_"):]
        abp_name = abp_name[:-2] if abp_name.endswith("_C") else abp_name
        preset = presets.get(key)
        preset_path = c["presets"] or (("/Game/" + preset[len(CONTENT):].replace(".uasset", "") + "." + preset.split("/")[-1].replace(".uasset", "")) if preset else None)
        ms = montage_set(key, c["body"])
        e = {
            "id": key, "name": NAMES.get(key, f["name"]), "formName": f["name"], "form": f["form"], "formEditorId": f["editorId"], "blueprint": c["bp"],
            "body": c["body"], "parts": EXTRA_PARTS.get(key, []) + list(c["parts"].values()),
            "abp": f"/Game/Dev/Animation/Blueprints/Reverse/Creatures/{abp_name}.{abp_name}_C",
            "presets": preset_path,
            **ms, "sounds": sounds_of(key), "damage": (esm.get(f["form"]) or {}).get("damage"), "combatLoco": (ms["montageDir"] or key) in combat_loco, "reach": REACH.get(key), "alternatives": [x["bp"].split("/")[-1] for x in cands[1:]],
        }
        e["missing"] = [k for k in ("body", "presets", "power") if not e[k]] + ([] if e["attacks"] else ["attacks"])
        inv[key] = e

    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    with open(os.path.join(ROOT, "data", "creatures_inventory.json"), "w", encoding="utf-8") as fo:
        json.dump(inv, fo, indent=2, ensure_ascii=False)

    print("\n4. result")
    order = []
    for g, ids in INCLUDE.items():
        for i in ids:
            e = inv.get(i)
            state = "MISSING entirely" if not e else ("ok" if not e["missing"] else "missing " + ",".join(e["missing"]))
            print(f"   [{g}] {i:15} {state:30} {(e or {}).get('name')}  {(e or {}).get('montageDir')}  parts={len((e or {}).get('parts', []))}")
            if e and "body" not in e["missing"] and "presets" not in e["missing"]:
                order.append((g, i))
    others = sorted(set(inv) - {i for ids in INCLUDE.values() for i in ids})
    print("   not included:", ", ".join(others))

    # Lua
    def lstr(s):
        return "nil" if s is None else '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    lines = ["-- GENERATED by Transform/tools/creature_inventory.py: do not edit by hand.",
             "-- Transformation creatures: paths read from the game paks (form, Blueprint, AnimBlueprint, montage).",
             "return {",
             "  order = { " + ", ".join(lstr(i) for _, i in order) + " },",
             "  creatures = {"]
    for g, i in order:
        e = inv[i]
        lines.append(f"    {i} = {{ group = {lstr(g)}, name = {lstr(e['name'])}, form = 0x{e['form']:08X}, reach = {e['reach'] or 'nil'}, combatLoco = {'true' if e['combatLoco'] else 'false'},")
        lines.append(f"        body = {lstr(e['body'])}, abp = {lstr(e['abp'])}, presets = {lstr(e['presets'])},")
        lines.append(f"        parts = {{ {', '.join(lstr(p) for p in e['parts'])} }},")
        lines.append(f"        attacks = {{ {', '.join(lstr(p) for p in e['attacks'])} }}, power = {lstr(e['power'])},")
        lines.append(f"        recoil = {lstr(e['recoil'])}, stagger = {lstr(e['stagger'])},")
        snd = ", ".join(f"{t} = {lstr(v)}" for t, v in sorted(e["sounds"].items()))
        lines.append(f"        sounds = {{ {snd} }} }},")
    lines.append("  },")
    lines.append("}")
    with open(os.path.join(ROOT, "lua", "SefiroTransformation", "Scripts", "creatures_data.lua"), "w", encoding="utf-8", newline="\n") as fo:
        fo.write("\n".join(lines) + "\n")

    # C#
    cs = ["// GENERATED by Transform/tools/creature_inventory.py: do not edit by hand.",
          "namespace Sefiro.TransformationMenu.Common;", "", "public static partial class CreatureCatalog", "{",
          "    /// <summary>(id, group, displayed name, TES form, attack damage from the CREA record) in bestiary order.</summary>",
          "    public static readonly (string Id, string Group, string Name, uint Form, int Damage)[] Generated =", "    ["]
    for g, i in order:
        e = inv[i]
        cs.append(f'        ("{i}", "{g}", "{e["name"]}", 0x{e["form"]:08X}, {e["damage"] or 0}),')
    cs += ["    ];", "", "    public static readonly (string Id, string Title)[] Groups =", "    ["]
    for g, t in GROUP_TITLES.items():
        cs.append(f'        ("{g}", "{t}"),')
    cs += ["    ];", "}"]
    with open(os.path.join(ROOT, "mod", "Sefiro.TransformationMenu.Common", "CreatureCatalog.g.cs"), "w", encoding="utf-8", newline="\n") as fo:
        fo.write("\n".join(cs) + "\n")
    print(f"\n   written: {len(order)} creatures in creatures_data.lua and CreatureCatalog.g.cs")

    # "hand-held" items (weapons, shields, torches) for the server: as a creature the character stays unarmed
    import esm_hand_items
    items = esm_hand_items.hand_items()
    hs = ["// GENERATED by Transform/tools/creature_inventory.py (esm_hand_items.py): do not edit by hand.",
          "// Runtime IDs according to Plugins.txt: " + ", ".join(f"{i:02X} {n}" for i, n in enumerate(esm_hand_items.load_order())),
          "namespace Sefiro.TransformationMenu.Client;", "", "internal static class HandItems", "{",
          "    /// <summary>Weapons (bows included), shields and torches: as a creature they must be removed (animations the creature lacks).</summary>",
          "    public static readonly HashSet<uint> Ids =", "    ["]
    ids = sorted(items)
    for k in range(0, len(ids), 8):
        hs.append("        " + ", ".join(f"0x{x:08X}" for x in ids[k:k + 8]) + ",")
    hs += ["    ];", "}"]
    with open(os.path.join(ROOT, "mod", "Sefiro.TransformationMenu.Client", "HandItems.g.cs"), "w", encoding="utf-8", newline="\n") as fo:
        fo.write("\n".join(hs) + "\n")
    print(f"   written: {len(ids)} hand-held items in HandItems.g.cs")


if __name__ == "__main__":
    sys.exit(main())
