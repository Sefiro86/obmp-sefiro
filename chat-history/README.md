# Chat History

Chat History brings shell-style command history to the OblivionMP chat. Open the chat, press **Up** to bring back the line you sent last, keep pressing to go further back, and press **Down** to return to what you were typing. The history survives game restarts, so the commands you use every day are always one key away.

It is built for players and server admins who type the same commands over and over and are tired of copying them from somewhere else.

## Features

- **Up and Down** browse every line you sent, newest first.
- **Your draft is safe**: start typing, browse the history, press Down past the newest line and your unfinished text comes back.
- **Kept across sessions**: up to 200 lines are saved on your PC and loaded the next time you play.
- **No duplicates**: sending a line again moves it to the top instead of adding a copy.
- **Server-wide**: install it once on the server and every player who connects gets it automatically.
- **Fails safe**: if the client mod is missing, the chat works as before, with a history that lasts for the current session.

## Requirements

| | Version |
|---|---|
| OblivionMP server | 1.1.0 |
| OblivionMP.Chat (ships with the server) | 1.1.0 |
| Windows PowerShell | 5.1 or later (included in Windows 10 and 11) |

Players need nothing extra: the server hands them the mod when they connect.

## Installation

Install on the **server**. You need the release zip, `Sefiro.ChatHistory-<version>.zip`, from the [Releases page](https://github.com/Sefiro86/obmp-sefiro/releases).

1. **Stop the server.**
2. **Extract the zip** anywhere, for example to your Downloads folder.
3. **Open PowerShell** in the extracted `Sefiro.ChatHistory-<version>` folder: Shift + right-click inside the folder, then *Open PowerShell window here*.
4. **Run the installer**, replacing the path with your server folder (the one that contains `mods`):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install.ps1 -ServerPath "D:\OblivionMP\Server"
   ```

   `-ExecutionPolicy Bypass` lets this one script run without changing your system settings. Windows blocks scripts downloaded from the internet by default.
5. **Start the server.** Players who connect get the mod and the new chat page.

The installer:

- copies the mod to `mods\Sefiro.ChatHistory`;
- saves OblivionMP's original chat page as `mods\OblivionMP.Chat\client\web\chat.js.sefiro-backup`;
- installs the chat page with history in its place.

### Manual installation

1. Copy `mods\Sefiro.ChatHistory` from the release folder into your server's `mods` folder.
2. In your server, back up `mods\OblivionMP.Chat\client\web\chat.js`.
3. Replace it with `chat\chat.js` from the release folder.

## Using it

1. Press the chat key and type as usual.
2. Press **Up** to fill the line with the last thing you sent; press it again to go further back.
3. Press **Down** to move forward; past the newest line you get your draft back.
4. Press **Enter** to send. Edit the line first if you need to.

The history is personal: each player keeps their own, on their own PC.

## Updating

Stop the server, extract the new release and run its `Install.ps1` with the same `-ServerPath`. Your original backup is kept, and players keep their history.

## Uninstalling

Stop the server and run, from the release folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1 -ServerPath "D:\OblivionMP\Server"
```

It restores OblivionMP's original chat page and removes the mod. Each player's history file stays on their PC until they delete it.

## Where the history is stored

On each player's PC:

```
%LOCALAPPDATA%\Sefiro\ChatHistory\history.txt
```

It is plain text, one line per entry, oldest first. Delete it to clear your history.

## Troubleshooting

**"chat.js is not the OblivionMP.Chat 1.1.0 page this release was made for"**
ReadyM probably updated their chat. The installer changed nothing, so your server is untouched. Look for a newer Chat History release. If you know what you are doing, run the installer again with `-Force`.

**"The server is running"**
Stop the server first: it keeps its files open, and players would get a mix of old and new files.

**Up and Down do nothing**
The chat page was not replaced. Check that the server's `mods\OblivionMP.Chat\client\web\chat.js` starts with a comment mentioning Chat History. Run the installer again if it does not, and make sure players reconnect after the server restarts.

**The history is lost when the game restarts**
The client mod is not loaded. Check that `mods\Sefiro.ChatHistory` exists on the server, and look for `[ChatHistory] Client loaded` in the game's `UE4SS.log`.

**After an OblivionMP update the history keys stopped working**
Updates to OblivionMP.Chat replace its chat page. Run `Install.ps1` again; if the new page differs, wait for a Chat History update.

## How it works

The OblivionMP chat is a web page shown by the game's embedded browser. Its script only handles Enter and Escape, so Chat History adds Up and Down to it. The page cannot keep data across restarts: the embedded browser has no on-disk profile, so `localStorage` is wiped when the game closes. The page therefore asks the `Sefiro.ChatHistory` client mod for the saved history when it loads (`SefiroChatHistoryLoad`) and sends it every line you submit (`SefiroChatHistoryAdd`). The mod writes the file.

The server half of the mod does nothing except make the server hand the mod to every player.

## Building from source

Requires the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0); the ReadyM SDK packages come from NuGet.

```powershell
cd chat-history
.\build.ps1
```

The release folder and zip are written to `chat-history\dist`.

`chat\chat.js` is generated from OblivionMP.Chat 1.1.0's original page by `tools\make_chat_js.py`, which refuses any other version:

```powershell
python tools\make_chat_js.py <path to the original chat.js> chat\chat.js
```

## Credits and license

Made by **Sefiro**. The Chat History code is released under the [MIT license](../LICENSE).

`chat/chat.js` is the chat page of OblivionMP.Chat by **ReadyM**, included with the Chat History additions so the mod can be installed in one step. The original page belongs to ReadyM; it will be removed from this repository at their request. OblivionMP and OblivionMP.Chat are made by ReadyM; this project is not affiliated with or endorsed by ReadyM or Bethesda.
