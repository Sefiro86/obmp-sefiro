using Microsoft.Extensions.Logging;
using ReadyM.Api.DI;
using ReadyM.Cef.Rpc;
using ReadyM.SDK.Attributes;

namespace Sefiro.TransformationMenu.Client;

[ModEntry]
public sealed partial class Mod(TransformState state, IDependencyContainer services, ILogger logger)
{
    private void Init()
    {
        logger.LogInformation("[Transform] client loaded (menu: Alt+U)");
        state.Reset();
        // native core for unequip/equip while transformed into a creature (see GameCommands, Unarmed)
        GameCommands.Start(ModDirectory, logger);
        // Required in 1.1: without this registration the menu page and the game cannot hear each other (web-ui docs).
        services.RegisterSingleton<ICefRpcHandler>(services.Resolve<TransformMenu>());
    }
}
