using System.Diagnostics;
using Microsoft.Extensions.Logging;
using OblivionMP.SDK;
using OblivionMP.SDK.Common.Archetypes.Mixins;
using ReadyM.SDK.Attributes;
using Sefiro.TransformationMenu.Common;

namespace Sefiro.TransformationMenu.Client;

// Unarmed while transformed into a creature. With a weapon, a shield or a torch in hand the game asks the body for
// animations (one-handed, two-handed, bow, torch) that creatures do not have: the body froze and slid (deer,
// 2026-11-17; unequipping the sword from the inventory made it move again).
// What to take off:
//  1. main, no lists: the Lua reads on the pawn's weapons component the forms of the weapon and shield in hand
//     (WeaponForm/ShieldForm, m_formID) and HandRelay passes them here. Works for weapons of any mod, enchanted too;
//  2. fallback: the list generated from the game plugins (HandItems), mostly for torches, checked on the local
//     character's equipment.
// Everything runs on this client, on the local player only: real unequip/equip through the native core
// (GameCommands), which ReadyM then syncs like an inventory click. The items held when transforming are equipped
// again when going back; items taken in hand later are only removed. Race forms (character packs) use the human
// animations: weapons stay there.
// Cost: one pass over the local equipment per second, only while transformed into a creature.
[Service]
public sealed partial class Unarmed(IPlayers players, TransformState state, ILogger logger)
{
    private readonly List<uint> _restore = [];           // held when transforming: equipped again afterwards
    private readonly Dictionary<uint, long> _lastUnequip = [];
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private bool _creature;
    private bool _firstReport;
    private long _nextCheckMs;

    /// <summary>Weapon and shield in hand reported by the Lua (0 = nothing).</summary>
    public void Report(uint weapon, uint shield)
    {
        if (!_creature) return;
        foreach (var form in new[] { weapon, shield })
        {
            if (form == 0) continue;
            if (_firstReport && !_restore.Contains(form)) _restore.Add(form);
            Unequip(form);
        }
        _firstReport = false;
    }

    private void Update()
    {
        var me = players.LocalPlayer?.PlayerId;
        var creature = me is { } id && Creatures.IsCreature(state.CurrentFor(id));
        if (creature != _creature)
        {
            _creature = creature;
            if (creature)
            {
                _restore.Clear();
                _lastUnequip.Clear();
                _firstReport = true;
                StripListed(remember: true);
            }
            else
            {
                foreach (var form in _restore) Run("equipitem", form);
                if (_restore.Count > 0) logger.LogInformation("[Transform] re-equipped {Count} held item(s)", _restore.Count);
                _restore.Clear();
            }
        }
        if (!_creature) return;
        var now = _clock.ElapsedMilliseconds;
        if (now < _nextCheckMs) return;
        _nextCheckMs = now + 1000;
        StripListed(remember: false);
    }

    // Fallback: equipped items of the local character that are in the generated list (torches mostly).
    private void StripListed(bool remember)
    {
        if (players.LocalMainCharacter is not { } main) return;
        var equipment = main.As<Equipment>();
        var count = equipment.ItemsCount;
        for (var i = 0; i < count; i++)
        {
            var entry = equipment.GetItems(i);
            if (entry.Worn == 0) continue;
            var form = entry.FormId.FormId.Value;
            if (!HandItems.Ids.Contains(form)) continue;
            if (remember && !_restore.Contains(form)) _restore.Add(form);
            Unequip(form);
        }
    }

    private void Unequip(uint form)
    {
        var now = _clock.ElapsedMilliseconds;   // no repeated commands while ReadyM syncs the change
        if (_lastUnequip.TryGetValue(form, out var last) && now - last < 3000) return;
        _lastUnequip[form] = now;
        Run("unequipitem", form);
    }

    private void Run(string command, uint form)
    {
        var ticket = GameCommands.Run($"player.{command} {form:X8} 0");
        if (ticket <= 0) logger.LogWarning("[Transform] {Command} {Form:X8} not run (code {Code})", command, form, ticket);
    }
}
