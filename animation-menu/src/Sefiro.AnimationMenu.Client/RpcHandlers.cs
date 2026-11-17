using Sefiro.AnimationMenu.Common;
using ReadyM.Api.Idents;
using ReadyM.SDK.Attributes;

namespace Sefiro.AnimationMenu.Client;

// A command from the menu of another player in the area: it is passed to the Lua on this PC with the "r " prefix.
// The prefix tells the Lua that the command did not come from this PC, so it is ignored: another player's menu never
// moves the local player. This channel is kept for a later version that shows the animation to the other players.
[RpcHandlersFor(typeof(AnimationMenuRpc))]
public sealed partial class RpcHandlers(AnimFiles files)
{
    partial void OnAnimationMenuCommand(PlayerId sender, string command)
    {
        if (AnimCommands.IsValid(command) && !AnimCommands.IsLocal(command)) files.Push("r " + command);
    }
}
