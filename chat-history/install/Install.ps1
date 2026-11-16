<#
.SYNOPSIS
    Installs Chat History on an OblivionMP server.

.DESCRIPTION
    1. Copies the Sefiro.ChatHistory mod into the server's "mods" folder. The server hands its client
       half to every player who connects.
    2. Replaces the chat page of OblivionMP.Chat (mods\OblivionMP.Chat\client\web\chat.js) with the
       version that adds Up/Down history, after saving the original as chat.js.sefiro-backup.

    Stop the server before running this script. Run it again after an OblivionMP update: if ReadyM
    changed their chat page, the script stops and tells you, instead of overwriting their new file.

.PARAMETER ServerPath
    The OblivionMP server folder, the one that contains the "mods" folder.

.PARAMETER Force
    Replace chat.js even if it is not the OblivionMP.Chat 1.1.0 page this release was made for.

.EXAMPLE
    .\Install.ps1 -ServerPath "D:\OblivionMP\Server"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ServerPath,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$ModId = 'Sefiro.ChatHistory'
$Marker = 'Chat History feature by Sefiro'
# SHA-256 of OblivionMP.Chat 1.1.0 client/web/chat.js, with line endings normalized to LF.
$OriginalSha256 = '0c24feab29b92ceec98c4746db7f22d352dce639864e24d20eb02de47675c5fa'

function Get-NormalizedSha256([string] $Path) {
    $text = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

$here = $PSScriptRoot
$mods = Join-Path $ServerPath 'mods'
$chatJs = Join-Path $mods 'OblivionMP.Chat\client\web\chat.js'
$backup = "$chatJs.sefiro-backup"
$sourceMod = Join-Path $here "mods\$ModId"
$sourceChat = Join-Path $here 'chat\chat.js'

if (-not (Test-Path $mods)) { throw "No 'mods' folder in '$ServerPath'. Pass the OblivionMP server folder with -ServerPath." }
if (-not (Test-Path $chatJs)) { throw "OblivionMP.Chat is not installed on this server ('$chatJs' is missing)." }
if (-not (Test-Path $sourceMod) -or -not (Test-Path $sourceChat)) { throw "Run this script from the extracted release folder (mods\$ModId and chat\chat.js are missing)." }

$fullServer = (Resolve-Path $ServerPath).Path
$running = Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($fullServer, [StringComparison]::OrdinalIgnoreCase) }
if ($running) { throw "The server is running ($($running[0].ProcessName)). Stop it, then run this script again." }

# 1. Chat page
$current = [System.IO.File]::ReadAllText($chatJs)
if ($current.Contains($Marker)) {
    Write-Host "chat.js already has Chat History: updating it."
}
else {
    $hash = Get-NormalizedSha256 $chatJs
    if ($hash -ne $OriginalSha256 -and -not $Force) {
        throw "chat.js is not the OblivionMP.Chat 1.1.0 page this release was made for (ReadyM may have updated it). Nothing was changed. Check for a newer Chat History release, or run again with -Force to replace it anyway."
    }
    Copy-Item $chatJs $backup -Force
    Write-Host "Saved the original chat page as $backup"
}
Copy-Item $sourceChat $chatJs -Force
Write-Host "Installed the chat page with history: $chatJs"

# 2. Mod
$target = Join-Path $mods $ModId
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
Copy-Item $sourceMod $mods -Recurse -Force
Write-Host "Installed the mod: $target"

Write-Host ""
Write-Host "Done. Start the server; players get the mod and the new chat page when they connect."
Write-Host "In game, open the chat and press Up and Down to browse the lines you sent before."
