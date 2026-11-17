using System.Diagnostics;
using System.Text;
using Microsoft.Extensions.Logging;
using Sefiro.TransformationMenu.Common;
using OblivionMP.SDK;
using OblivionMP.SDK.Archetypes.Mixins;
using ReadyM.Api.Idents;
using ReadyM.SDK.Attributes;

namespace Sefiro.TransformationMenu.Client;

/// <summary>Animation events received from other players, waiting to be written out for the Lua.</summary>
[Service]
public sealed partial class AnimInbox
{
    private readonly Queue<(PlayerId Who, string Anim)> _queue = new();
    public void Add(PlayerId who, string anim) { lock (_queue) _queue.Enqueue((who, anim)); }
    public bool TryTake(out (PlayerId Who, string Anim) item) { lock (_queue) return _queue.TryDequeue(out item); }
}

// Synchronizes the animations the Lua plays by hand (creature attacks): the transformed player's attack does not go
// through ReadyM's animation system, so other players would not see it.
//   outgoing: the Lua writes anim_out.txt ("<seq> <anim>" per line, last 20); the new lines are sent here to the other
//             players in the area with the TransformAnim RPC (ClientToClients, server relay).
//   incoming: received events become lines "<seq> 0x<pawn> <anim>" in anim_in.txt (last 20), which the Lua on this
//             PC plays on that player's pawn.
[Service]
public sealed partial class AnimRelay(RpcHandlers rpc, AnimInbox inbox, IPlayers players, TransformState state, ILogger logger)
{
    private static readonly string Folder = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ReadyM.Launcher", "Oblivion", "Mods", "SefiroTransformation");
    private static readonly string OutPath = Path.Combine(Folder, "anim_out.txt");
    private static readonly string InPath = Path.Combine(Folder, "anim_in.txt");
    private const int Keep = 20;
    private const int MaxAnimLength = 24;

    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private long _nextPollMs;
    private long _lastOutSeq = -1;          // -1: first read, events already in the file are skipped
    private DateTime _lastOutWrite;         // timestamp of the last anim_out.txt read: if unchanged it is not re-read
    private long _inSeq;
    private readonly Queue<string> _inLines = new();

    private void Start()
    {
        // incoming file is emptied on every client start
        TryWrite(InPath, "");
    }

    private void Update()
    {
        var now = _clock.ElapsedMilliseconds;
        if (now < _nextPollMs) return;
        _nextPollMs = now + 40;
        // the Lua writes anim_out.txt only for creature attacks: if the local player is not transformed into a
        // creature (normal or "race" form) there is nothing to read
        if (players.LocalPlayer?.PlayerId is { } me && Creatures.IsCreature(state.CurrentFor(me))) SendOutgoing();
        else _lastOutSeq = -1;              // on the next transformation old events are ignored
        WriteIncoming();
    }

    private void SendOutgoing()
    {
        string text;
        try
        {
            var info = new FileInfo(OutPath);
            if (!info.Exists) return;
            var written = info.LastWriteTimeUtc;
            if (written == _lastOutWrite && _lastOutSeq >= 0) return;   // unchanged: no read
            text = File.ReadAllText(OutPath);
            _lastOutWrite = written;
        }
        catch (IOException) { return; }   // the Lua is writing it: retry in 40 ms

        var events = new List<(long Seq, string Anim)>();
        long maxSeq = 0;
        foreach (var line in text.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var parts = line.Split(' ', 2);
            if (parts.Length != 2 || !long.TryParse(parts[0], out var seq)) continue;
            var anim = parts[1];
            if (anim.Length == 0 || anim.Length > MaxAnimLength) continue;
            events.Add((seq, anim));
            if (seq > maxSeq) maxSeq = seq;
        }
        if (_lastOutSeq < 0)                 // first read: old events are not sent
        {
            _lastOutSeq = maxSeq;
            return;
        }
        if (maxSeq < _lastOutSeq) _lastOutSeq = 0;   // the Lua restarted and counts from the start
        foreach (var (seq, anim) in events)
            if (seq > _lastOutSeq) rpc.SendTransformAnim(anim);
        if (maxSeq > _lastOutSeq) _lastOutSeq = maxSeq;
    }

    private void WriteIncoming()
    {
        var changed = false;
        while (inbox.TryTake(out var item))
        {
            var pawn = PawnOf(item.Who);
            if (pawn == IntPtr.Zero) continue;   // player out of area or not shown yet
            _inLines.Enqueue($"{++_inSeq} 0x{(long)pawn:X} {item.Anim}");
            while (_inLines.Count > Keep) _inLines.Dequeue();
            changed = true;
        }
        if (changed) TryWrite(InPath, string.Join('\n', _inLines) + "\n");
    }

    private IntPtr PawnOf(PlayerId who)
    {
        foreach (var ch in players.AreaPlayers)
            if (ch.PlayerId == who) return ch.As<MappedActor>().Pawn;
        return IntPtr.Zero;
    }

    private void TryWrite(string path, string text)
    {
        if (!Directory.Exists(Folder)) return;
        try
        {
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, text, Encoding.ASCII);
            File.Move(tmp, path, true);
        }
        catch (Exception e)
        {
            logger.LogWarning("[Transform] cannot write {File}: {Error}", path, e.Message);
        }
    }
}
