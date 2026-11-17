using System.Diagnostics;
using System.Text;
using Microsoft.Extensions.Logging;
using Sefiro.TransformationMenu.Common;
using OblivionMP.SDK;
using OblivionMP.SDK.Archetypes.Mixins;
using ReadyM.Api.Idents;
using ReadyM.SDK.Attributes;

namespace Sefiro.TransformationMenu.Client;

// Tracks who is transformed and writes it to state.txt for the SefiroTransformation UE4SS Lua mod, which changes
// the appearance in game. Lines: "self <creature>" for the local player, "0x<pawn> <creature>" for the
// others (MappedActor.Pawn: used only as a key to find the actor again, never to read memory).
[Service]
public sealed partial class TransformState(IPlayers players, ILogger logger)
{
    private static readonly string Folder = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ReadyM.Launcher", "Oblivion", "Mods", "SefiroTransformation");
    private static readonly string FilePath = Path.Combine(Folder, "state.txt");

    private readonly Dictionary<PlayerId, string> _creatures = [];
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private long _nextCheckMs;
    private string? _written;
    private bool _warnedMissing;

    public void Set(PlayerId who, string creature)
    {
        if (string.IsNullOrEmpty(creature)) _creatures.Remove(who);
        else if (Creatures.IsKnown(creature)) _creatures[who] = creature;
        logger.LogInformation("[Transform] {Player} -> {Creature}", who, creature == "" ? "normal" : creature);
        _nextCheckMs = 0;
    }

    /// <summary>Creature of the given player ("" = normal).</summary>
    public string CurrentFor(PlayerId who) => _creatures.TryGetValue(who, out var c) ? c : "";

    public void Reset()
    {
        _creatures.Clear();
        Write("v1\n");
    }

    private void Update()
    {
        var now = _clock.ElapsedMilliseconds;
        if (now < _nextCheckMs) return;
        _nextCheckMs = now + 250;
        // nobody transformed (the normal case): no strings to build, Write returns immediately if already so
        if (_creatures.Count == 0) { Write("v1\n"); return; }
        Write(BuildText());
    }

    private string BuildText()
    {
        var text = new StringBuilder("v1\n");
        if (_creatures.Count == 0) return text.ToString();
        var me = players.LocalPlayer?.PlayerId;
        foreach (var (who, creature) in _creatures)
        {
            if (me is { } id && id == who)
            {
                text.Append("self ").Append(creature).Append('\n');
                continue;
            }
            foreach (var ch in players.AreaPlayers)
            {
                if (ch.PlayerId != who) continue;
                var pawn = ch.As<MappedActor>().Pawn;
                if (pawn != IntPtr.Zero)
                    text.Append("0x").Append(((long)pawn).ToString("X")).Append(' ').Append(creature).Append('\n');
                break;
            }
        }
        return text.ToString();
    }

    private void Write(string text)
    {
        if (text == _written) return;
        if (!Directory.Exists(Folder))
        {
            if (!_warnedMissing)
                logger.LogWarning("[Transform] UE4SS mod SefiroTransformation not installed ({Folder}): creatures will not show", Folder);
            _warnedMissing = true;
            return;
        }
        try
        {
            var tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, text);
            File.Move(tmp, FilePath, true);
            _written = text;
        }
        catch (Exception e)
        {
            logger.LogWarning("[Transform] cannot write {File}: {Error}", FilePath, e.Message);
        }
    }
}
