<#
.SYNOPSIS
    Installs the Spriggan character pack on an OblivionMP server, for every player.

.DESCRIPTION
    Copies the character into the server's modloader. The ReadyM launcher copies everything in it to every player's PC
    before the game starts, so players install nothing by hand:
      Paks\~mods\0000_ObmpSpriggan_P.*   -> modloader\@GAME\Content\Paks\~mods
      Data\ObmpSpriggan.esp              -> modloader\@GAME\Content\Dev\ObvData\Data, added to the modloader's Plugins.txt
      ...\packs\spriggan.json            -> modloader\@APPDATA\Mods\SefiroTransformation\packs

    The modloader's Plugins.txt replaces every player's Plugins.txt. If it does not exist yet, it is created from the
    Plugins.txt of the game on this PC (the full load order), then ObmpSpriggan.esp is added at the end.

    Needs Sefiro Transformation Menu 0.9.2 or later on the server, installed with its own Install-Server.ps1.
    Stop the server before running this script, and start it again afterwards: the server reads the modloader when it
    starts.

.PARAMETER ServerPath
    The OblivionMP server folder, the one that contains the "mods" and "modloader" folders.

.PARAMETER GamePath
    The Oblivion Remastered folder (the one that contains "OblivionRemastered"), used only to create the modloader's
    Plugins.txt the first time. If omitted, the Steam libraries are searched.

.EXAMPLE
    .\Install-Server.ps1 -ServerPath "D:\OblivionMP\Server"
.EXAMPLE
    .\Install-Server.ps1 -ServerPath "D:\OblivionMP\Server" -GamePath "D:\Games\Oblivion Remastered"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ServerPath,
    [string] $GamePath
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'ServerModloader.ps1')

$ServerPath = Assert-ServerFolder $ServerPath
if (-not (Test-Path (Join-Path $ServerPath 'mods\Sefiro.TransformationMenu'))) {
    Write-Warning 'Sefiro Transformation Menu is not installed on this server. The Spriggan needs it: install it with its Install-Server.ps1.'
}
$modloader = Get-ServerModloader $ServerPath
if (-not $modloader) {
    throw "No 'modloader' folder in $ServerPath, so the Spriggan cannot be sent to players. Each player must run Install-Client.ps1 on their PC instead."
}

# Checks and Plugins.txt first: if a file is empty or the game cannot be found, nothing has been changed yet.
Assert-NoEmptyFiles (Get-PackageFiles $here)
Add-ModloaderPlugins $modloader (Get-PackagePlugins $here) $GamePath
$count = Copy-PackageToModloader $here $modloader
Write-Host "Copied $count files to $modloader."
Write-Host 'Start the server again: every player receives the Spriggan from the ReadyM launcher when they join.'
Write-Host 'Open the transformation menu with Alt+U: it is under Characters.'
