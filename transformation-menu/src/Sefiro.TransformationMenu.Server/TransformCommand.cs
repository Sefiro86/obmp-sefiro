using System.Numerics;
using Microsoft.Extensions.Logging;
using Sefiro.TransformationMenu.Common;
using OblivionMp.ChatMod.Common;
using OblivionMp.ChatMod.Serverside;
using OblivionMP.SDK.Common.Archetypes;
using OblivionMP.SDK.Common.Archetypes.Mixins;
using OblivionMP.SDK.Serverside;
using OblivionMP.SDK.Serverside.Spawners;
using ReadyM.Relay.Common.Oblivion;
using ReadyM.Relay.Common.Oblivion.ECS.Values;
using ReadyM.Api.Idents;
using ReadyM.SDK.Archetypes.Core;
using ReadyM.SDK.Attributes;
using ReadyM.SDK.Server.Entities;
using ReadyM.SDK.Server.Events;
using ServerPlayers = ReadyM.Relay.Server.Sdk.Players.IPlayers;

namespace Sefiro.TransformationMenu.Server;

// /transform <creature> | off | list. The server tracks who is transformed and sends it to ALL clients
// (including those who join later), so each can show the creature in place of that player.
[Service]
public sealed partial class TransformCommand(
    IChat chat,
    IServerEvents events,
    IEntities entities,
    RpcHandlers rpc,
    TransformRequests requests,
    CreatureDamage damage,
    ServerRefIds refIds,
    ServerPlayers players,
    TransformConfig config,
    ILogger logger)
{
    private readonly Dictionary<PlayerId, string> _state = [];
    private readonly Dictionary<PlayerId, uint> _loaders = [];   // player -> RefId of the loader creature
    private readonly List<(uint RefId, long At)> _expiring = [];    // loader creatures to remove
    private readonly System.Diagnostics.Stopwatch _clock = System.Diagnostics.Stopwatch.StartNew();
    // Test 2026-11-16 03:28: at -50 m the game brought the troll back to the surface and it attacked the guards.
    // Now it spawns dead (Hp 0): the game still loads its mesh and AnimBlueprint, but it does not fight; after 8 s it
    // is removed (the player's Lua and nearby ones have already applied the body, which from then on keeps the assets
    // in memory).
    private const long LoaderLifetimeMs = 8000;

    // Marks this mod's loader creatures (no game spawner has this ref id).
    private const uint LoaderMarker = 0xFFFFFFF2;
    // 50 m below the feet: out of sight and combat, but in a loaded cell.
    private static readonly Vector3 LoaderOffset = new(0f, 0f, -5000f);

    private void Start()
    {
        chat.AddCommand("transform", "/transform <creature>|off|list - look like a creature (needs the SefiroTransformation client mod)", OnCommand);
        events.OnPlayerConnected += OnPlayerConnected;

        events.OnPlayerDisconnected += OnPlayerDisconnected;
    }

    private void Stop()
    {
        events.OnPlayerConnected -= OnPlayerConnected;
        events.OnPlayerDisconnected -= OnPlayerDisconnected;
    }

    private void OnCommand(IChat c, PlayerId sender, string arguments)
    {
        var arg = (arguments ?? "").Trim().ToLowerInvariant();
        if (arg is "" or "list")
        {
            c.SendTo(sender, "Creatures: " + string.Join(", ", Creatures.Names) + ". Use /transform off to go back.", ChatLineKind.CommandReply);
            return;
        }
        if (!IsAllowed(sender))
        {
            c.SendTo(sender, "You are not allowed to use this command.", ChatLineKind.CommandReply);
            return;
        }
        if (arg is "off" or "none" or "normal")
        {
            _state.Remove(sender);
            damage.Set(sender, "");
            RemoveLoader(sender);
            Broadcast(sender, "");
            c.SendTo(sender, "Back to normal.", ChatLineKind.CommandReply);
            return;
        }
        if (!Creatures.IsKnown(arg))
        {
            c.SendTo(sender, $"Unknown creature '{arg}'. Try: {string.Join(", ", Creatures.Names)}.", ChatLineKind.CommandReply);
            return;
        }
        _state[sender] = arg;
        damage.Set(sender, arg);
        // 0.2.2: no loader creature (it appeared alive next to the player, test 03:35). The Lua uses Altar's
        // preloading (VPairedAssetsLoadingSubsystem). SpawnLoader is kept for reference, unused.
        RemoveLoader(sender);
        Broadcast(sender, arg);
        c.SendTo(sender, $"You are now a {arg}. Others with the client mod see it too.", ChatLineKind.CommandReply);
        logger.LogInformation("[Transform] {Player} -> {Creature}", sender, arg);
    }

    private void Broadcast(PlayerId who, string creature)
    {
        foreach (var p in entities.Query<Player>())
            rpc.SendTransformState(p.PlayerId, who, creature);
    }

    private void OnPlayerConnected(Player player, Guid readyMId)
    {
        foreach (var (who, creature) in _state)
            rpc.SendTransformState(player.PlayerId, who, creature);
    }

    private void OnPlayerDisconnected(Player player, Guid readyMId, LiteNetLib.DisconnectReason reason)
    {
        RemoveLoader(player.PlayerId);
        damage.Set(player.PlayerId, "");
        if (_state.Remove(player.PlayerId))
            Broadcast(player.PlayerId, "");
    }

    // Game creature under the player: the game loads its assets with its normal pipeline (also on the other clients
    // in the zone), so the Lua finds them in memory without LoadAsset. Same pattern as NpcTest/Ambush.
    private void SpawnLoader(PlayerId player, string creature)
    {
        RemoveLoader(player);
        if (!Creatures.LoaderForms.TryGetValue(creature, out var form)) return;
        if (!entities.TryLookup(player, out MainCharacter main)
            || main.ParentCellKind == ParentCellKind.Unknown
            || !entities.TryGetScope(main, out Area area)
            || !entities.TryLookup(main.As<ParentCell>().ToFullCellId(area.AreaId), out Cell cell))
        {
            logger.LogWarning("[Transform] {Player}: character or cell not ready, no loader creature", player);
            return;
        }
        var owner = cell.MasterClient != PlayerId.Invalid ? cell.MasterClient : player;
        var npc = entities.Create<Npc>(cell, owner);
        npc.RefId = refIds.Next();
        npc.BaseId = new FormId(form);
        npc.SpawnerRefId = LoaderMarker;
        npc.Level = main.Level;
        npc.Position = main.Position + LoaderOffset;
        npc.Rotation = main.Rotation;
        npc.Hp = 0f;
        _loaders[player] = npc.RefId;
        _expiring.Add((npc.RefId, _clock.ElapsedMilliseconds + LoaderLifetimeMs));
        logger.LogInformation("[Transform] loader {Form:X8} ref {Ref:X8} under {Player}", form, npc.RefId, player);
    }

    private void Update()
    {
        // choices from the clients' Alt+U menu: same logic (permissions, state, synchronization) as /transform
        while (requests.TryTake(out var req))
            OnCommand(chat, req.Who, req.Creature);

        if (_expiring.Count == 0) return;
        var now = _clock.ElapsedMilliseconds;
        for (var i = _expiring.Count - 1; i >= 0; i--)
        {
            if (_expiring[i].At > now) continue;
            var refId = _expiring[i].RefId;
            _expiring.RemoveAt(i);
            foreach (var (p, r) in _loaders.ToList())
                if (r == refId) _loaders.Remove(p);
            DeleteLoader(refId);
        }
    }

    private void RemoveLoader(PlayerId player)
    {
        if (!_loaders.Remove(player, out var refId)) return;
        _expiring.RemoveAll(e => e.RefId == refId);
        DeleteLoader(refId);
    }

    private void DeleteLoader(uint refId)
    {
        Npc? found = null;
        foreach (var npc in entities.Query<Npc>())
        {
            if (npc.SpawnerRefId == LoaderMarker && npc.RefId == refId) { found = npc; break; }
        }
        if (found is { } n) entities.Delete(n);
    }

    private bool IsAllowed(PlayerId player)
    {
        if (config.AllowedAccounts.Count == 0)
            return true;
        return players.GetReadyMId(player) is { } account
               && config.AllowedAccounts.Any(a => Guid.TryParse(a, out var g) && g == account);
    }
}
