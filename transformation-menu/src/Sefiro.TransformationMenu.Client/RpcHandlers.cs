using Sefiro.TransformationMenu.Common;
using ReadyM.Api.Idents;
using ReadyM.SDK.Attributes;

namespace Sefiro.TransformationMenu.Client;

[RpcHandlersFor(typeof(TransformRpc))]
public sealed partial class RpcHandlers(TransformState state, AnimInbox inbox)
{
    partial void OnTransformState(PlayerId who, string creature) => state.Set(who, creature);

    partial void OnTransformAnim(PlayerId sender, string anim)
    {
        if (anim is "attack1" or "attack2" or "power") inbox.Add(sender, anim);
    }
}
