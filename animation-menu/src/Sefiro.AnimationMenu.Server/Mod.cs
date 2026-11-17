using Microsoft.Extensions.Logging;
using Sefiro.AnimationMenu.Common;
using ReadyM.SDK.Attributes;

namespace Sefiro.AnimationMenu.Server;

// The server only relays commands (ClientToClients, area of interest): there is no logic here.
[ModEntry]
public sealed partial class Mod(ILogger logger)
{
    private void Init() => logger.LogInformation("[AnimationMenu] loaded: relay of the Alt+Y animation menu");
}

[RpcHandlersFor(typeof(AnimationMenuRpc))]
public sealed partial class RpcHandlers;
