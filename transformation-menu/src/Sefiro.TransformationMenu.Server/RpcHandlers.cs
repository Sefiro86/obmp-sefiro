using Sefiro.TransformationMenu.Common;
using ReadyM.Api.Idents;
using ReadyM.Relay.Server.Sdk.Rpc;
using ReadyM.SDK.Attributes;

namespace Sefiro.TransformationMenu.Server;

/// <summary>Requests from the clients' menu, drained by TransformCommand in its Update (no circular dependency).</summary>
[Service]
public sealed partial class TransformRequests
{
    private readonly Queue<(PlayerId Who, string Creature)> _queue = new();
    public void Add(PlayerId who, string creature) { lock (_queue) _queue.Enqueue((who, creature)); }
    public bool TryTake(out (PlayerId Who, string Creature) item) { lock (_queue) return _queue.TryDequeue(out item); }
}

// Receives the menu requests; the generated SendTransformState methods are used by TransformCommand.
[RpcHandlersFor(typeof(TransformRpc))]
public sealed partial class RpcHandlers(TransformRequests requests)
{
    partial void OnTransformRequest(RpcContext context, string creature)
    {
        if (creature is { Length: > 0 and <= 48 }) requests.Add(context.Sender, creature);
    }
}
