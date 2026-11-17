using ReadyM.Api.Idents;
using ReadyM.SDK.Attributes;

namespace Sefiro.TransformationMenu.Common;

// A single message: the server tells every client what a player looks like.
[RpcContracts]
public static partial class TransformRpc
{
    /// <summary>Player <paramref name="who"/> now looks like <paramref name="creature"/> ("" = normal).</summary>
    [ServerToClient] public static partial void TransformState(PlayerId who, string creature);

    /// <summary>
    /// A transformed player performed an action animated by hand from the Lua ("attack1", "attack2", "power"): the
    /// other players in the area play it on his pawn. The server only acts as a relay.
    /// </summary>
    [ClientToClients(RelayMode.AreaOfInterestOthers)] public static partial void TransformAnim(string anim);

    /// <summary>The transformation menu (Alt+U) requests a creature ("off" = normal): same logic as /transform.</summary>
    [ClientToServer] public static partial void TransformRequest(string creature);

}

/// <summary>
/// Available forms: the creatures of the generated catalog (CreatureCatalog.g.cs, from tools/creature_inventory.py,
/// the same script that writes creatures_data.lua for the Lua) plus character packs ("pack:id[:skin]", race forms).
/// </summary>
public static class Creatures
{
    /// <summary>(id, bestiary group, displayed name) of the game's creatures, in menu order.</summary>
    public static readonly (string Id, string Group, string Name)[] Entries =
        [.. CreatureCatalog.Generated.Select(c => (c.Id, c.Group, c.Name))];

    public static readonly string[] Names = [.. Entries.Select(e => e.Id)];

    /// <summary>
    /// Form of a character pack: "pack:&lt;id&gt;" or "pack:&lt;id&gt;:&lt;skin&gt;" (lowercase, digits, '_'). Packs
    /// live on the clients (packs\*.json of the Lua mod): the server only checks the format, and a client without
    /// the pack sees that player as normal.
    /// </summary>
    public static bool IsPack(string name) => PackName.IsMatch(name);
    private static readonly System.Text.RegularExpressions.Regex PackName =
        new(@"^pack:[a-z0-9_]{1,24}(:[a-z0-9_]{1,16})?$", System.Text.RegularExpressions.RegexOptions.CultureInvariant);

    public static bool IsKnown(string name) => Array.IndexOf(Names, name) >= 0 || IsPack(name);

    /// <summary>A real creature (own body and animations): not "" (normal) and not a character pack (race).</summary>
    public static bool IsCreature(string name) => name.Length > 0 && Array.IndexOf(Names, name) >= 0;

    /// <summary>
    /// TES forms of the creatures (m_formID). Used by the server's "loader creature", now unused: the Lua uses
    /// Altar's preloading. UE4SS LoadAsset inside the tick crashes (2026-11-16 03:21).
    /// </summary>
    public static readonly Dictionary<string, uint> LoaderForms = CreatureCatalog.Generated.ToDictionary(c => c.Id, c => c.Form);

    /// <summary>
    /// List for the menu page: entries "id|group|name|skin|color" separated by ';' (skin and color only for
    /// packs), then "@group|title" for the groups. <paramref name="packs"/>: entries of the packs available on the client.
    /// </summary>
    public static string MenuList(IEnumerable<string> packs) => string.Join(';',
        Entries.Select(e => $"{e.Id}|{e.Group}|{e.Name}").Concat(packs)
            .Concat(CreatureCatalog.Groups.Select(g => $"@{g.Id}|{g.Title}")).Append("@characters|Characters").Append("@detected|Detected characters"));
}
