using ReadyM.SDK.Attributes;

namespace Sefiro.AnimationMenu.Common;

// One message: a command of the animation menu (Alt+Y), relayed by the server to the players in the area.
// The menu does not send it yet (the target is only the local player): it is kept for a later version, in which the
// other players will see the animation on whoever plays it.
[RpcContracts]
public static partial class AnimationMenuRpc
{
    /// <summary>A Sefiro Animation Menu command (see <see cref="AnimCommands"/>).</summary>
    [ClientToClients(RelayMode.AreaOfInterestOthers)] public static partial void AnimationMenuCommand(string command);
}

/// <summary>
/// Commands understood by the SefiroAnimationMenu Lua (cmd.txt), all on the local player. One line, words separated
/// by spaces:
///   play &lt;anim&gt; &lt;loop 0|1&gt;   play an animation (short name, e.g. A_Humanoid_Cheer01 or AM_...)
///   speed &lt;x&gt;                speed 0..2 (0 = pause)
///   stop                     stop the animation and go back to normal
///   open / close             menu opened or closed (bench camera, cursor, player held still)
///   cam &lt;action&gt; [arg]      bench camera (next, prev, preset n, orbit ±1, height ±1, zoom ±1,
///                            move orbitP|heightN|zoom0..., drag dx_dy, spin, reset)
///   seek &lt;s&gt;                 jump to that point of the animation (click on the timeline)
///   step &lt;1|-1&gt;             one frame (1/30 s) forward/back, while paused
///   mark &lt;a|b&gt; / abclear     mark the start/end of the section to repeat / clear it
///   refpose                  the mesh's rest pose (no animation)
///   home                     the player goes back to where they were when the menu opened (after root motion)
///   root &lt;on|off&gt;            root motion: on = the animation moves the character; off = it stays in place
///   fav &lt;anim&gt;               favorite yes/no
///   mode &lt;pure|slot&gt;        pure = the mesh plays only the animation (rig check); slot = inside the AnimBlueprint
///   scan                     the Lua rewrites the list of animations
/// </summary>
public static class AnimCommands
{
    public const int MaxLength = 120;

    public static bool IsValid(string command)
    {
        if (string.IsNullOrWhiteSpace(command) || command.Length > MaxLength) return false;
        foreach (var c in command)
            if (!(char.IsAsciiLetterOrDigit(c) || c is ' ' or '_' or '.' or '-')) return false;
        var verb = command.Split(' ', 2)[0];
        return verb is "play" or "speed" or "stop" or "mode" or "step" or "mark"
            or "abclear" or "refpose" or "fav" or "scan" or "open" or "close" or "cam" or "seek" or "home" or "root";
    }

    /// <summary>Commands that only concern this PC (all the others could be sent to other players later).</summary>
    public static bool IsLocal(string command) =>
        command is "scan" or "open" or "close" || command.StartsWith("fav ") || command.StartsWith("cam ");
}
