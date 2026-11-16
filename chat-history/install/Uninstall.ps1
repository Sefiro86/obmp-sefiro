<#
.SYNOPSIS
    Removes Chat History from an OblivionMP server.

.DESCRIPTION
    Restores the original OblivionMP.Chat page from chat.js.sefiro-backup and deletes the
    Sefiro.ChatHistory mod folder. Players keep their saved history file
    (%LOCALAPPDATA%\Sefiro\ChatHistory\history.txt) unless they delete it.

    Stop the server before running this script.

.PARAMETER ServerPath
    The OblivionMP server folder, the one that contains the "mods" folder.

.EXAMPLE
    .\Uninstall.ps1 -ServerPath "D:\OblivionMP\Server"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ServerPath
)

$ErrorActionPreference = 'Stop'
$ModId = 'Sefiro.ChatHistory'
$Marker = 'Chat History feature by Sefiro'

$mods = Join-Path $ServerPath 'mods'
$chatJs = Join-Path $mods 'OblivionMP.Chat\client\web\chat.js'
$backup = "$chatJs.sefiro-backup"
$target = Join-Path $mods $ModId

if (-not (Test-Path $mods)) { throw "No 'mods' folder in '$ServerPath'. Pass the OblivionMP server folder with -ServerPath." }

$fullServer = (Resolve-Path $ServerPath).Path
$running = Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($fullServer, [StringComparison]::OrdinalIgnoreCase) }
if ($running) { throw "The server is running ($($running[0].ProcessName)). Stop it, then run this script again." }

if (Test-Path $backup) {
    Copy-Item $backup $chatJs -Force
    Remove-Item $backup -Force
    Write-Host "Restored the original chat page: $chatJs"
}
elseif ((Test-Path $chatJs) -and ([System.IO.File]::ReadAllText($chatJs).Contains($Marker))) {
    Write-Warning "No backup of the original chat page was found. Reinstall OblivionMP.Chat to get it back; until then the chat keeps working, with session-only history."
}
else {
    Write-Host "The chat page is already the original one."
}

if (Test-Path $target) {
    Remove-Item $target -Recurse -Force
    Write-Host "Removed the mod: $target"
}
else {
    Write-Host "The mod was not installed."
}

Write-Host ""
Write-Host "Done. Start the server again."
