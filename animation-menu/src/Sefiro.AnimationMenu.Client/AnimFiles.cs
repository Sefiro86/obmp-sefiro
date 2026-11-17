using System.Text;
using Microsoft.Extensions.Logging;
using ReadyM.SDK.Attributes;

namespace Sefiro.AnimationMenu.Client;

// File exchange with the UE4SS Lua mod SefiroAnimationMenu (in the Lua mod's own folder):
//   cmd.txt   (here -> Lua) the last 30 commands, one "<seq> <command>" per line. The seq starts from the clock in ms,
//             so it keeps growing across restarts: the Lua never replays old commands.
//   list.txt  (Lua -> here) the animations for the current body and the state, shown in the Alt+Y menu.
[Service]
public sealed partial class AnimFiles(ILogger logger)
{
    public static readonly string Folder = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ReadyM.Launcher", "Oblivion", "Mods", "SefiroAnimationMenu");
    private static readonly string CmdPath = Path.Combine(Folder, "cmd.txt");
    private static readonly string ListPath = Path.Combine(Folder, "list.txt");
    private static readonly string PosPath = Path.Combine(Folder, "pos.txt");
    private const int Keep = 30;

    private readonly object _lock = new();
    private readonly Queue<string> _lines = new();
    private long _seq = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
    private DateTime _listStamp;
    private bool _warnedMissing;

    public void Push(string command)
    {
        lock (_lock)
        {
            _lines.Enqueue($"{++_seq} {command}");
            while (_lines.Count > Keep) _lines.Dequeue();
            Write(CmdPath, string.Join('\n', _lines) + "\n");
        }
    }

    /// <summary>The text of list.txt if it changed since the last read, otherwise null.</summary>
    public string? ReadListIfChanged()
    {
        try
        {
            var stamp = File.GetLastWriteTimeUtc(ListPath);
            if (stamp == _listStamp || !File.Exists(ListPath)) return null;
            var text = File.ReadAllText(ListPath);
            _listStamp = stamp;
            return text;
        }
        catch (IOException) { return null; }   // the Lua is writing it: try again on the next round
    }

    public void ForgetList() => _listStamp = default;

    private string? _lastPos;

    /// <summary>"position length" of the animation playing (the Lua's pos.txt) if it changed, otherwise null.</summary>
    public string? ReadPosIfChanged()
    {
        try
        {
            if (!File.Exists(PosPath)) return null;
            var text = File.ReadAllText(PosPath).Trim();
            if (text == _lastPos) return null;
            _lastPos = text;
            return text;
        }
        catch (IOException) { return null; }
    }

    public void ForgetPos() => _lastPos = null;

    private void Write(string path, string text)
    {
        if (!Directory.Exists(Folder))
        {
            if (!_warnedMissing)
                logger.LogWarning("[AnimationMenu] UE4SS mod SefiroAnimationMenu not installed ({Folder})", Folder);
            _warnedMissing = true;
            return;
        }
        try
        {
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, text, Encoding.ASCII);
            File.Move(tmp, path, true);
        }
        catch (Exception e)
        {
            logger.LogWarning("[AnimationMenu] cannot write {File}: {Error}", path, e.Message);
        }
    }
}
