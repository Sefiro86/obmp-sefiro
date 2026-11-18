<#
.SYNOPSIS
    Builds Sefiro Animation Menu and packages the release zip.

.DESCRIPTION
    Output (in animation-menu\dist):
      Sefiro.AnimationMenu-<version>\
        dogma-package.json                                          package identity for DogmaModInstaller
        mods\Sefiro.AnimationMenu\manifest.json, client\, server\   the OblivionMP mod, for the server's mods folder
        client-appdata\Mods\SefiroAnimationMenu\                    the UE4SS Lua mod, for the server's
                                                                    modloader\@APPDATA (or each player's PC)
        Install-Server.ps1, Uninstall-Server.ps1, ServerModloader.ps1, Install-Client.ps1, Uninstall-Client.ps1,
        README.md, CHANGELOG.md, LICENSE
      Sefiro.AnimationMenu-<version>.zip

    The folder layout is the one DogmaModInstaller reads, so the release installs with either tool.

    Requires the .NET 10 SDK. The version comes from src\Content\manifest.json.
#>
[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')][string] $Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$src = Join-Path $root 'src'
$manifest = Get-Content (Join-Path $src 'Content\manifest.json') -Raw | ConvertFrom-Json
$version = $manifest.version
$modId = $manifest.uniqueId
$name = "$modId-$version"
$dist = Join-Path $root 'dist'
$out = Join-Path $dist $name

Write-Host "Building $modId $version ($Configuration)"
dotnet build (Join-Path $src 'Sefiro.AnimationMenu.sln') -c $Configuration -v minimal -warnaserror
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
$zip = "$out.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

$mod = Join-Path $out "mods\$modId"
$client = Join-Path $mod 'client'
$server = Join-Path $mod 'server'
New-Item -ItemType Directory -Force $client, $server | Out-Null

$clientBin = Join-Path $src "Sefiro.AnimationMenu.Client\bin\$Configuration\net10.0"
$serverBin = Join-Path $src "Sefiro.AnimationMenu.Server\bin\$Configuration\net10.0"
Copy-Item (Join-Path $clientBin 'Sefiro.AnimationMenu.Client.dll'), (Join-Path $clientBin 'Sefiro.AnimationMenu.Common.dll') $client
Copy-Item (Join-Path $src 'Sefiro.AnimationMenu.Client\web') $client -Recurse
Copy-Item (Join-Path $serverBin 'Sefiro.AnimationMenu.Server.dll'), (Join-Path $serverBin 'Sefiro.AnimationMenu.Common.dll') $server
Copy-Item (Join-Path $src 'Content\manifest.json') $mod

$appMods = Join-Path $out 'client-appdata\Mods'
New-Item -ItemType Directory -Force $appMods | Out-Null
Copy-Item (Join-Path $root 'lua\*') $appMods -Recurse
$meta = [ordered]@{ id = $modId; name = $manifest.name; version = $version } | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $out 'dogma-package.json'), $meta, (New-Object Text.UTF8Encoding $false))
foreach ($file in 'Install-Server.ps1', 'Uninstall-Server.ps1', 'Install-Client.ps1', 'Uninstall-Client.ps1') {
    Copy-Item (Join-Path $root "install\$file") $out
}
Copy-Item (Join-Path $root '..\shared\ServerModloader.ps1') $out
Copy-Item (Join-Path $root 'README.md'), (Join-Path $root 'CHANGELOG.md') $out
Copy-Item (Join-Path $root '..\LICENSE') $out

# The ReadyM launcher cannot send empty files from a server's modloader: fail the build instead of shipping one.
$empty = @(Get-ChildItem $out -Recurse -File | Where-Object { $_.Length -eq 0 })
if ($empty.Count -gt 0) { throw "Empty files in the release: $($empty.FullName -join ', ')" }

# Zip with "/" separators (Compress-Archive in Windows PowerShell 5.1 writes "\", which breaks unzip on Linux).
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$base = Split-Path $out -Parent
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    Get-ChildItem $out -Recurse -File | ForEach-Object {
        $entry = $_.FullName.Substring($base.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $entry, 'Optimal') | Out-Null
    }
} finally { $archive.Dispose() }
Write-Host "Release folder: $out"
Write-Host "Release zip:    $zip"
