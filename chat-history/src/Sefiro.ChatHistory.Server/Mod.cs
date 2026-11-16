using Microsoft.Extensions.Logging;
using ReadyM.SDK.Attributes;

namespace Sefiro.ChatHistory.Server;

// Everything happens on the client. The server half only exists so the server hands the mod
// to every player who connects.
[ModEntry]
public sealed partial class Mod(ILogger logger)
{
    private void Init() => logger.LogInformation("[ChatHistory] Loaded (client-side chat history)");
}
