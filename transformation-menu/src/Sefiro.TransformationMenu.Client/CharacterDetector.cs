using System.IO.Compression;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Sefiro.TransformationMenu.Client;

// Automatic detection of custom characters (2026-11-17). A humanoid custom character is a new race:
//  1. a new RACE record in an unofficial plugin (listed in Plugins.txt), plus the NPC_ records of the same plugin that
//     use it (the game needs them to preload it);
//  2. the race's Unreal asset in a pak under Content\Paks\~mods: the .utoc contains "<EditorID>.uasset" in plain text
//     in its name table (verified on the Succubus pak).
// For every race found without a hand-written JSON pack, packs\auto_<id>.json is generated (group "detected",
// no skins): the Lua and the menu read it like any other pack. auto_ files that are no longer valid are deleted.
// Cost: one read of the unofficial plugins (small) and of the .utoc files in ~mods, once at client start.
internal static class CharacterDetector
{
    // plugins shipped with the game: no custom races, and Oblivion.esm is huge
    private static readonly HashSet<string> Official = new(StringComparer.OrdinalIgnoreCase)
    {
        "Oblivion.esm", "DLCBattlehornCastle.esp", "DLCFrostcrag.esp", "DLCHorseArmor.esp", "DLCMehrunesRazor.esp",
        "DLCOrrery.esp", "DLCShiveringIsles.esp", "DLCSpellTomes.esp", "DLCThievesDen.esp", "DLCVileLair.esp",
        "Knights.esp", "AltarESPMain.esp", "AltarDeluxe.esp", "AltarGymNavigation.esp", "TamrielLeveledRegion.esp",
    };

    private sealed record Race(string EditorId, string Name, uint Id, List<uint> Npcs);

    /// <summary>Writes/updates the automatic packs. Returns how many are active.</summary>
    public static int Run(string content, IReadOnlyList<string> plugins, string packFolder, ILogger logger)
    {
        Directory.CreateDirectory(packFolder);
        // races already covered by hand-written packs
        var handRaces = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var f in Directory.GetFiles(packFolder, "*.json"))
        {
            if (Path.GetFileName(f).StartsWith("auto_", StringComparison.OrdinalIgnoreCase)) continue;
            try
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(f));
                if (doc.RootElement.TryGetProperty("race", out var r)) handRaces.Add(r.GetString() ?? "");
            }
            catch { /* broken pack: PackCatalog reports it */ }
        }

        var utocs = Directory.Exists(Path.Combine(content, "Paks", "~mods"))
            ? Directory.GetFiles(Path.Combine(content, "Paks", "~mods"), "*.utoc").Select(File.ReadAllBytes).ToList()
            : [];
        var data = Path.Combine(content, "Dev", "ObvData", "Data");
        var written = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var plugin in plugins)
        {
            if (Official.Contains(plugin)) continue;
            List<Race> races;
            try { races = ReadRaces(Path.Combine(data, plugin)); }
            catch (Exception e) { logger.LogWarning("[Transform] detector: {Plugin} unreadable: {Error}", plugin, e.Message); continue; }
            foreach (var race in races)
            {
                var path = $"/Game/Forms/actors/race/{race.EditorId}.{race.EditorId}";
                if (handRaces.Contains(path)) continue;
                var needle = Encoding.ASCII.GetBytes(race.EditorId + ".uasset");
                if (!utocs.Any(u => u.AsSpan().IndexOf(needle) >= 0))
                {
                    logger.LogInformation("[Transform] detector: race {Race} in {Plugin} has no Unreal asset in ~mods", race.EditorId, plugin);
                    continue;
                }
                if (race.Npcs.Count == 0)
                {
                    logger.LogInformation("[Transform] detector: race {Race} has no NPC to preload it, skipped", race.EditorId);
                    continue;
                }
                var id = Sanitize(race.EditorId);
                var file = Path.Combine(packFolder, $"auto_{id}.json");
                var json = JsonSerializer.Serialize(new
                {
                    format = 1, auto = true, id, name = race.Name, group = "detected", race = path,
                    requires = new { plugin },
                    preload = race.Npcs.Take(2).Select(n => new { plugin, id = (n & 0xFFFFFF).ToString("X6") }),
                }, new JsonSerializerOptions { WriteIndented = true });
                if (!File.Exists(file) || File.ReadAllText(file) != json) File.WriteAllText(file, json);
                written.Add(Path.GetFileName(file));
                logger.LogInformation("[Transform] detector: {Race} ({Name}) from {Plugin} -> {File}", race.EditorId, race.Name, plugin, Path.GetFileName(file));
            }
        }
        foreach (var old in Directory.GetFiles(packFolder, "auto_*.json"))
            if (!written.Contains(Path.GetFileName(old))) File.Delete(old);
        return written.Count;
    }

    private static string Sanitize(string editorId)
    {
        var s = new string(editorId.ToLowerInvariant().Where(c => c is >= 'a' and <= 'z' or >= '0' and <= '9' or '_').ToArray());
        if (s.EndsWith("race") && s.Length > 4) s = s[..^4];
        return s.Length > 24 ? s[..24] : s.Length == 0 ? "race" : s;
    }

    // ---- minimal reader for a TES4 plugin: RACE (EDID, FULL) and NPC_ (RNAM) of the plugin's new records
    private static List<Race> ReadRaces(string path)
    {
        var data = File.ReadAllBytes(path);
        var hdrSize = BitConverter.ToInt32(data, 4);
        var masters = 0;
        foreach (var (type, _) in Subrecords(data.AsSpan(20, hdrSize).ToArray()))
            if (type == "MAST") masters++;
        var races = new Dictionary<uint, Race>();
        var npcs = new List<(uint Id, uint Race)>();
        Walk(data, 20 + hdrSize, data.Length, (type, id, body) =>
        {
            if (id >> 24 != masters) return;   // record from a master, not new
            if (type == "RACE")
            {
                string edid = "", full = "";
                foreach (var (st, v) in Subrecords(body))
                {
                    if (st == "EDID") edid = ZString(v);
                    else if (st == "FULL") full = ZString(v);
                }
                if (edid.Length > 0) races[id] = new Race(edid, full.Length > 0 ? full : edid, id, []);
            }
            else if (type == "NPC_")
            {
                foreach (var (st, v) in Subrecords(body))
                    if (st == "RNAM" && v.Length >= 4) npcs.Add((id, BitConverter.ToUInt32(v, 0)));
            }
        });
        foreach (var (npc, race) in npcs)
            if (races.TryGetValue(race, out var r)) r.Npcs.Add(npc);
        return [.. races.Values];
    }

    private static void Walk(byte[] data, int off, int end, Action<string, uint, byte[]> onRecord)
    {
        while (off + 20 <= end)
        {
            var type = Encoding.ASCII.GetString(data, off, 4);
            var size = BitConverter.ToInt32(data, off + 4);
            if (type == "GRUP") { Walk(data, off + 20, off + size, onRecord); off += size; continue; }
            var flags = BitConverter.ToUInt32(data, off + 8);
            var id = BitConverter.ToUInt32(data, off + 12);
            if (type is "RACE" or "NPC_")
            {
                var body = data.AsSpan(off + 20, size).ToArray();
                if ((flags & 0x00040000) != 0)
                {
                    using var z = new ZLibStream(new MemoryStream(body, 4, body.Length - 4), CompressionMode.Decompress);
                    using var ms = new MemoryStream();
                    z.CopyTo(ms);
                    body = ms.ToArray();
                }
                onRecord(type, id, body);
            }
            off += 20 + size;
        }
    }

    private static IEnumerable<(string Type, byte[] Value)> Subrecords(byte[] body)
    {
        var p = 0;
        while (p + 6 <= body.Length)
        {
            var type = Encoding.ASCII.GetString(body, p, 4);
            var size = BitConverter.ToUInt16(body, p + 4);
            yield return (type, body.AsSpan(p + 6, Math.Min(size, body.Length - p - 6)).ToArray());
            p += 6 + size;
        }
    }

    private static string ZString(byte[] v) => Encoding.Latin1.GetString(v).TrimEnd('\0');
}
