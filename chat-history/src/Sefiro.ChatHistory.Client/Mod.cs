using Microsoft.Extensions.Logging;
using ReadyM.SDK.Attributes;

namespace Sefiro.ChatHistory.Client;

// The SDK creates every [Service] while mods load, so HistoryStore registers its message
// handlers on its own; the entry point only reports that the mod is there.
[ModEntry]
public sealed partial class Mod(ILogger logger)
{
    private void Init() => logger.LogInformation("[ChatHistory] Client loaded");
}
