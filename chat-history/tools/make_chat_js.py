"""Builds chat-history/chat/chat.js from ReadyM's original OblivionMP.Chat 1.1.0 chat.js.

Usage: python make_chat_js.py <original chat.js> <output chat.js>

The original file belongs to ReadyM (OblivionMP.Chat). This script only adds the history feature:
Up/Down recall previously sent lines, and the history is stored by the Sefiro.ChatHistory client mod.
Every insertion is anchored to an exact line of the original, so a changed original fails loudly
instead of producing a broken page.
"""
import hashlib
import sys

ORIGINAL_SHA256 = "0c24feab29b92ceec98c4746db7f22d352dce639864e24d20eb02de47675c5fa"

HEADER = """// OblivionMP.Chat 1.1.0 chat page by ReadyM, with the Chat History feature by Sefiro
// (https://github.com/Sefiro86/obmp-sefiro). The original file belongs to ReadyM; the additions are
// marked "Chat History" and released under the MIT license.

"""

HISTORY = """
// Chat History: Up and Down bring back the lines you sent before, including those from previous
// sessions. The Sefiro.ChatHistory client mod keeps them in a file, because the game's browser does not
// save localStorage to disk. Without the mod the history only lasts for the current session.
const HISTORY_MAX = 200;
let chatHistory = [];    // oldest first
let historyAt = -1;      // -1 = editing a new line, not browsing
let historyDraft = '';   // what was being typed before pressing Up
(async () => {
  try {
    const text = await Promise.race([
      readym.request('SefiroChatHistoryLoad', ''),
      new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 3000)),
    ]);
    const saved = String(text || '').split(/\\r?\\n/).filter(Boolean);
    chatHistory = saved.concat(chatHistory.filter((line) => !saved.includes(line))).slice(-HISTORY_MAX);
  } catch (e) { /* Sefiro.ChatHistory is not installed: session-only history */ }
})();

function remember(text) {
  chatHistory = chatHistory.filter((line) => line !== text);
  chatHistory.push(text);
  if (chatHistory.length > HISTORY_MAX) chatHistory.shift();
  try { readym.postMessage('SefiroChatHistoryAdd', text); } catch (e) { /* mod not installed */ }
}

function browseHistory(step) {
  if (!chatHistory.length) return;
  if (historyAt === -1) {
    if (step > 0) return;
    historyDraft = entry.value;
    historyAt = chatHistory.length;
  }
  historyAt += step;
  if (historyAt < 0) historyAt = 0;
  if (historyAt >= chatHistory.length) {
    historyAt = -1;
    entry.value = historyDraft;
  } else {
    entry.value = chatHistory[historyAt];
  }
  const end = entry.value.length;
  entry.setSelectionRange(end, end);
}
"""


def replace_once(text, old, new):
    if text.count(old) != 1:
        sys.exit(f"anchor not found exactly once: {old!r}")
    return text.replace(old, new)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    raw = open(src, "rb").read()
    digest = hashlib.sha256(raw.replace(b"\r\n", b"\n")).hexdigest()
    if digest != ORIGINAL_SHA256:
        sys.exit(f"unexpected original chat.js (sha256 {digest}); expected OblivionMP.Chat 1.1.0")
    s = raw.decode("utf-8").replace("\r\n", "\n")
    s = replace_once(s, "let fadeTimer = 0;\n", "let fadeTimer = 0;\n" + HISTORY)
    s = replace_once(s, "  entry.value = '';\n  entry.blur();\n",
                     "  entry.value = '';\n  historyAt = -1;   // Chat History\n  entry.blur();\n")
    s = replace_once(s, "  if (e.key !== 'Enter') return;\n",
                     "  // Chat History: Up and Down browse the lines sent before.\n"
                     "  if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {\n"
                     "    e.preventDefault();\n"
                     "    browseHistory(e.key === 'ArrowUp' ? -1 : 1);\n"
                     "    return;\n"
                     "  }\n\n"
                     "  if (e.key !== 'Enter') return;\n")
    s = replace_once(s, "  if (text) readym.sendSubmit(text);\n",
                     "  historyAt = -1;   // Chat History\n"
                     "  if (text) {\n"
                     "    remember(text);   // Chat History\n"
                     "    readym.sendSubmit(text);\n"
                     "  }\n")
    open(dst, "w", encoding="utf-8", newline="\n").write(HEADER + s)
    print("written", dst)


if __name__ == "__main__":
    main()
