using Microsoft.Extensions.Logging;
using Sefiro.TransformationMenu.Common;
using OblivionMP.SDK.Common.Archetypes;
using OblivionMP.SDK.Common.Events;
using ReadyM.Api.Idents;
using ReadyM.SDK.Attributes;
using ReadyM.SDK.Events;

namespace Sefiro.TransformationMenu.Server;

// Creature damage (2026-11-17). While transformed, the hit is still computed by the game using the hidden character
// (wielded weapon or fists). Here, before the server applies it, every damage whose attacker is a transformed
// player becomes the creature's attack damage (CREA record, CreatureCatalog.Generated.Damage): the character's
// weapon no longer matters. Cost: one dictionary lookup per health change, no extra traffic.
[Service]
public sealed partial class CreatureDamage(ILogger logger)
{
    private readonly Dictionary<PlayerId, int> _damage = [];
    private static readonly Dictionary<string, int> ByCreature =
        CreatureCatalog.Generated.Where(c => c.Damage > 0).ToDictionary(c => c.Id, c => c.Damage);
    private int _logged;

    /// <summary>Current form of the player ("" = normal): creatures without a known damage keep the game's damage.</summary>
    public void Set(PlayerId player, string creature)
    {
        if (creature.Length > 0 && ByCreature.TryGetValue(creature, out var d)) _damage[player] = d;
        else _damage.Remove(player);
    }

    [EventHandler(Stage.Filter)]
    public void Apply(ref HealthChangedEvent e, EventContext ctx)
    {
        if (_damage.Count == 0 || e.Amount >= 0f) return;            // nobody transformed, or it is not damage
        if (e.Attacker is not { } attacker || !attacker.TryAs(out MainCharacter main)) return;
        if (!_damage.TryGetValue(main.PlayerId, out var d)) return;
        var before = e.Amount;
        e.Amount = -d;
        if (_logged < 5)   // the first few times in the log, to check the sign and values in game
        {
            _logged++;
            logger.LogInformation("[Transform] creature damage: {Player} {Before} -> {After}", main.PlayerId, before, e.Amount);
        }
    }
}
