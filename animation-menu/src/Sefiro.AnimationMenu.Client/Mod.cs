using Microsoft.Extensions.Logging;
using ReadyM.Api.DI;
using ReadyM.Cef.Rpc;
using ReadyM.SDK.Attributes;

namespace Sefiro.AnimationMenu.Client;

[ModEntry]
public sealed partial class Mod(IDependencyContainer services, ILogger logger)
{
    private void Init()
    {
        logger.LogInformation("[AnimationMenu] client loaded (menu: Alt+Y)");
        // Required in 1.1: without this registration the menu page and the game cannot talk (docs: web-ui).
        services.RegisterSingleton<ICefRpcHandler>(services.Resolve<AnimMenu>());
    }
}
