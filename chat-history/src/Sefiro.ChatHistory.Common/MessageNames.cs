namespace Sefiro.ChatHistory.Common;

/// <summary>
/// Names of the messages exchanged between the chat page (chat.js) and the client mod.
/// They must match the names used in chat/chat.js.
/// </summary>
public static class MessageNames
{
    /// <summary>
    /// Request sent by the page when it loads (<c>readym.request</c>). The reply is the saved history,
    /// one line per entry, oldest first.
    /// </summary>
    public const string Load = "SefiroChatHistoryLoad";

    /// <summary>Message posted by the page (<c>readym.postMessage</c>) with a line the player just sent.</summary>
    public const string Add = "SefiroChatHistoryAdd";
}
