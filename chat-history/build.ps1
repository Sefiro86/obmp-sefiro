<#
.SYNOPSIS
    Builds Chat History and packages the release zip.

.DESCRIPTION
    Output (in chat-history\dist):
      Sefiro.ChatHistory-<version>\
        mods\Sefiro.ChatHistory\manifest.json, client\, server\   the mod, ready for a server's mods folder
        chat\chat.js                                             the OblivionMP.Chat page with history
        Install.ps1, Uninstall.ps1, README.md, CHANGELOG.md, LICENSE
      Sefiro.ChatHistory-<version>.zip

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
dotnet build (Join-Path $src 'Sefiro.ChatHistory.sln') -c $Configuration -v minimal -warnaserror
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
$zip = "$out.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

$mod = Join-Path $out "mods\$modId"
$client = Join-Path $mod 'client'
$server = Join-Path $mod 'server'
New-Item -ItemType Directory -Force $client, $server, (Join-Path $out 'chat') | Out-Null

$clientBin = Join-Path $src "Sefiro.ChatHistory.Client\bin\$Configuration\net10.0"
$serverBin = Join-Path $src "Sefiro.ChatHistory.Server\bin\$Configuration\net10.0"
Copy-Item (Join-Path $clientBin 'Sefiro.ChatHistory.Client.dll'), (Join-Path $clientBin 'Sefiro.ChatHistory.Common.dll') $client
Copy-Item (Join-Path $serverBin 'Sefiro.ChatHistory.Server.dll'), (Join-Path $serverBin 'Sefiro.ChatHistory.Common.dll') $server
Copy-Item (Join-Path $src 'Content\manifest.json') $mod

Copy-Item (Join-Path $root 'chat\chat.js') (Join-Path $out 'chat')
Copy-Item (Join-Path $root 'install\Install.ps1'), (Join-Path $root 'install\Uninstall.ps1') $out
Copy-Item (Join-Path $root 'README.md'), (Join-Path $root 'CHANGELOG.md') $out
Copy-Item (Join-Path $root '..\LICENSE') $out

Compress-Archive -Path $out -DestinationPath $zip
Write-Host "Release folder: $out"
Write-Host "Release zip:    $zip"
