using System.Diagnostics;
using System.Globalization;
using Sefiro.TransformationMenu.Common;
using OblivionMP.SDK;
using ReadyM.SDK.Attributes;

namespace Sefiro.TransformationMenu.Client;

// Items held by the player transformed into a creature: the Lua reads them from the pawn's weapon component
// (WeaponForm and ShieldForm, m_formID) and writes them to hand.txt ("<weapon> <shield>" in hex, 0 = nothing) only
// when they change. Here they are sent to the server (TransformHand RPC), which unequips them: no weapon lists, it
// also works for weapons from other mods.
// Read only while a creature and only if the file's timestamp changed.
[Service]
public sealed partial class HandRelay(Unarmed unarmed, IPlayers players, TransformState state)
{
    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ReadyM.Launcher", "Oblivion", "Mods", "SefiroTransformation", "hand.txt");

    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private long _nextPollMs;
    private DateTime _lastWrite;
    private (uint W, uint S) _lastSent = (uint.MaxValue, uint.MaxValue);

    private void Update()
    {
        var now = _clock.ElapsedMilliseconds;
        if (now < _nextPollMs) return;
        _nextPollMs = now + 250;
        if (players.LocalPlayer?.PlayerId is not { } me || !Creatures.IsCreature(state.CurrentFor(me)))
        {
            _lastSent = (uint.MaxValue, uint.MaxValue);   // on the next transformation everything is sent again
            return;
        }
        try
        {
            var info = new FileInfo(FilePath);
            if (!info.Exists || info.LastWriteTimeUtc == _lastWrite) return;
            _lastWrite = info.LastWriteTimeUtc;
            var parts = File.ReadAllText(FilePath).Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (parts.Length < 2
                || !uint.TryParse(parts[0], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var w)
                || !uint.TryParse(parts[1], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var s)) return;
            if ((w, s) == _lastSent || (w == 0 && s == 0 && _lastSent == (uint.MaxValue, uint.MaxValue))) return;
            _lastSent = (w, s);
            if (w != 0 || s != 0) unarmed.Report(w, s);
        }
        catch (IOException) { }   // the Lua is writing it: retry in 250 ms
    }
}
