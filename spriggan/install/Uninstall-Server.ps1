<#
.SYNOPSIS
    Removes the Spriggan character pack from an OblivionMP server.

.DESCRIPTION
    Deletes the files Install-Server.ps1 put in the server's modloader (pak, ObmpSpriggan.esp, spriggan.json) and
    removes ObmpSpriggan.esp from the modloader's Plugins.txt. Ask players to turn back to normal first.

    Stop the server before running this script, and start it again afterwards. Players keep their local copy until they
    run Uninstall-Client.ps1; without spriggan.json from the server the menu no longer lists it.

.PARAMETER ServerPath
    The OblivionMP server folder, the one that contains the "mods" and "modloader" folders.

.EXAMPLE
    .\Uninstall-Server.ps1 -ServerPath "D:\OblivionMP\Server"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ServerPath
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'ServerModloader.ps1')

$ServerPath = Assert-ServerFolder $ServerPath
$modloader = Get-ServerModloader $ServerPath
if (-not $modloader) { Write-Host 'This server has no modloader folder: nothing to remove.'; return }
$count = Remove-PackageFromModloader $here $modloader
Remove-ModloaderPlugins $modloader (Get-PackagePlugins $here)
Write-Host "Removed $count files from $modloader. Start the server again."
