using System.Text.Json;
using Microsoft.Extensions.Logging;
using ReadyM.SDK.Attributes;

namespace Sefiro.TransformationMenu.Client;

// Character packs on the client: the packs\*.json files of the SefiroTransformation Lua mod, the same ones the Lua
// reads. A pack is available if its pak is in Content\Paks\~mods and its plugin is in Plugins.txt: otherwise it does
// not appear in the menu (a release without a character does not show it). Read once at startup.
[Service]
public sealed partial class PackCatalog(ILogger logger)
{
    private static readonly string PackFolder = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ReadyM.Launcher", "Oblivion", "Mods", "SefiroTransformation", "packs");

    /// <summary>Menu entries: "pack:id[:skin]|group|name|skin name|color".</summary>
    public IReadOnlyList<string> MenuEntries { get; private set; } = [];

    private void Start()
    {
        var entries = new List<string>();
        var content = GameContentFolder();
        var ordered = content is null ? [] : Plugins(content);
        var plugins = new HashSet<string>(ordered.Select(x => x.ToLowerInvariant()));
        // custom characters without a hand-written pack: packs\auto_*.json (CharacterDetector)
        if (content is not null)
        {
            try
            {
                var found = CharacterDetector.Run(content, ordered, PackFolder, logger);
                logger.LogInformation("[Transform] detector: {Count} character(s) detected", found);
            }
            catch (Exception e) { logger.LogWarning("[Transform] detector failed: {Error}", e.Message); }
        }
        if (!Directory.Exists(PackFolder)) { MenuEntries = entries; return; }
        foreach (var file in Directory.GetFiles(PackFolder, "*.json"))
        {
            try
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(file));
                var root = doc.RootElement;
                var id = root.GetProperty("id").GetString() ?? "";
                if (!Common.Creatures.IsPack("pack:" + id)) { logger.LogWarning("[Transform] pack {File}: invalid id", file); continue; }
                if (root.TryGetProperty("requires", out var req))
                {
                    if (req.TryGetProperty("pak", out var pak) && content is not null
                        && !File.Exists(Path.Combine(content, "Paks", "~mods", pak.GetString() ?? "")))
                    { logger.LogInformation("[Transform] pack {Id} not available: pak missing", id); continue; }
                    if (req.TryGetProperty("plugin", out var plugin) && !plugins.Contains((plugin.GetString() ?? "").ToLowerInvariant()))
                    { logger.LogInformation("[Transform] pack {Id} not available: plugin not in Plugins.txt", id); continue; }
                }
                var name = root.TryGetProperty("name", out var n) ? n.GetString() ?? id : id;
                var group = root.TryGetProperty("group", out var g) ? g.GetString() ?? "characters" : "characters";
                var skins = root.TryGetProperty("skins", out var sk) && sk.ValueKind == JsonValueKind.Array ? sk.EnumerateArray().ToList() : [];
                if (skins.Count == 0) entries.Add($"pack:{id}|{group}|{Clean(name)}||");
                for (var i = 0; i < skins.Count; i++)
                {
                    var skinId = skins[i].TryGetProperty("id", out var si) ? si.GetString() ?? "" : "";
                    var key = i == 0 ? $"pack:{id}" : $"pack:{id}:{skinId}";
                    var skinName = skins[i].TryGetProperty("name", out var sn) ? sn.GetString() ?? skinId : skinId;
                    var color = skins[i].TryGetProperty("color", out var sc) ? sc.GetString() ?? "" : "";
                    entries.Add($"{key}|{group}|{Clean(name)}|{Clean(skinName)}|{Clean(color)}");
                }
                logger.LogInformation("[Transform] pack {Id}: {Skins} skin(s)", id, Math.Max(1, skins.Count));
            }
            catch (Exception e) { logger.LogWarning("[Transform] pack {File} unreadable: {Error}", file, e.Message); }
        }
        MenuEntries = entries;
    }

    // the menu format's separators cannot appear in the values
    private static string Clean(string s) => s.Replace("|", " ").Replace(";", ",");

    private static string? GameContentFolder()
    {
        // the client runs inside the game process: ...\OblivionRemastered\Binaries\Win64\*.exe
        var exe = Environment.ProcessPath;
        if (exe is null) return null;
        var content = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(exe)!, "..", "..", "Content"));
        return Directory.Exists(content) ? content : null;
    }

    // plugins in load order (Plugins.txt lines that exist in Data), with their original casing
    private static List<string> Plugins(string content)
    {
        var data = Path.Combine(content, "Dev", "ObvData", "Data");
        var list = new List<string>();
        var txt = Path.Combine(data, "Plugins.txt");
        if (!File.Exists(txt)) return list;
        foreach (var raw in File.ReadAllLines(txt))
        {
            var line = raw.Trim();
            if (line.Length > 0 && !line.StartsWith('#') && File.Exists(Path.Combine(data, line))) list.Add(line);
        }
        return list;
    }
}
