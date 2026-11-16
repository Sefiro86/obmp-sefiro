using System.Text;
using Microsoft.Extensions.Logging;
using ReadyM.Cef.Messaging;
using ReadyM.SDK.Attributes;
using Sefiro.ChatHistory.Common;

namespace Sefiro.ChatHistory.Client;

/// <summary>
/// Keeps the chat history in a file, so it survives game restarts: the game's embedded browser has no
/// on-disk profile, so the page's localStorage is lost every time the game closes.
/// </summary>
/// <remarks>
/// File: <c>%LOCALAPPDATA%\Sefiro\ChatHistory\history.txt</c>, one entry per line, oldest first,
/// at most <see cref="Capacity"/> entries and no duplicates (sending a line again moves it to the end).
/// The file lives outside the ReadyM folders, which the launcher manages.
/// </remarks>
[Service]
public sealed partial class HistoryStore(PageMessaging messages, PageMessageCallbackRegistry callbacks, ILogger logger)
{
    private const int Capacity = 200;
    private const int MaxLineLength = 240;   // same limit as the chat entry field

    private static readonly string Folder = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Sefiro", "ChatHistory");
    private static readonly string FilePath = Path.Combine(Folder, "history.txt");

    private readonly List<string> _lines = [];
    private readonly object _lock = new();

    private void Start()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                foreach (var line in File.ReadAllLines(FilePath, Encoding.UTF8))
                {
                    if (line.Length > 0) _lines.Add(line);
                }
            }
        }
        catch (Exception e)
        {
            logger.LogWarning("[ChatHistory] Could not read {File}: {Error}", FilePath, e.Message);
        }

        callbacks.Add(MessageNames.Load, OnLoad);
        callbacks.Add(MessageNames.Add, OnAdd);
        logger.LogInformation("[ChatHistory] Loaded {Count} entries from {File}", _lines.Count, FilePath);
    }

    private void OnLoad(PageMessageDelivery message)
    {
        if (message.RequestId == 0) return;   // a push without a request id expects no answer
        string text;
        lock (_lock) text = string.Join('\n', _lines);
        messages.ReplyText(message.Page, message.RequestId, MessageNames.Load, text);
    }

    private void OnAdd(PageMessageDelivery message)
    {
        var line = message.AsText().Replace('\r', ' ').Replace('\n', ' ').Trim();
        if (line.Length == 0 || line.Length > MaxLineLength) return;

        string[] snapshot;
        lock (_lock)
        {
            _lines.Remove(line);
            _lines.Add(line);
            if (_lines.Count > Capacity) _lines.RemoveRange(0, _lines.Count - Capacity);
            snapshot = [.. _lines];
        }

        try
        {
            Directory.CreateDirectory(Folder);
            var tmp = FilePath + ".tmp";
            File.WriteAllLines(tmp, snapshot, new UTF8Encoding(false));
            File.Move(tmp, FilePath, true);
        }
        catch (Exception e)
        {
            logger.LogWarning("[ChatHistory] Could not write {File}: {Error}", FilePath, e.Message);
        }
    }
}
