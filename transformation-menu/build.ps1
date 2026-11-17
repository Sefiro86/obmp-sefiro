<#
.SYNOPSIS
    Builds Sefiro Transformation Menu and packages the release zip.

.DESCRIPTION
    Output (in transformation-menu\dist):
      Sefiro.TransformationMenu-<version>\
        mods\Sefiro.TransformationMenu\manifest.json, client\, server\   the OblivionMP mod, for a server's mods folder
        lua\SefiroTransformation\                                        the UE4SS Lua mod, for each player's PC
        Install-Server.ps1, Install-Client.ps1, Uninstall-Client.ps1, README.md, CHANGELOG.md, LICENSE
      Sefiro.TransformationMenu-<version>.zip

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
dotnet build (Join-Path $src 'Sefiro.TransformationMenu.sln') -c $Configuration -v minimal -warnaserror
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
$zip = "$out.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

$mod = Join-Path $out "mods\$modId"
$client = Join-Path $mod 'client'
$server = Join-Path $mod 'server'
New-Item -ItemType Directory -Force $client, $server | Out-Null

$clientBin = Join-Path $src "Sefiro.TransformationMenu.Client\bin\$Configuration\net10.0"
$serverBin = Join-Path $src "Sefiro.TransformationMenu.Server\bin\$Configuration\net10.0"
Copy-Item (Join-Path $clientBin 'Sefiro.TransformationMenu.Client.dll'), (Join-Path $clientBin 'Sefiro.TransformationMenu.Common.dll') $client
Copy-Item (Join-Path $src 'Content\SefiroTransformation_native.native') $client
Copy-Item (Join-Path $src 'Sefiro.TransformationMenu.Client\web') $client -Recurse
Copy-Item (Join-Path $serverBin 'Sefiro.TransformationMenu.Server.dll'), (Join-Path $serverBin 'Sefiro.TransformationMenu.Common.dll') $server
Copy-Item (Join-Path $src 'Content\config.json') $server
Copy-Item (Join-Path $src 'Content\manifest.json') $mod

Copy-Item (Join-Path $root 'lua') $out -Recurse
Copy-Item (Join-Path $root 'install\Install-Server.ps1'), (Join-Path $root 'install\Install-Client.ps1'), (Join-Path $root 'install\Uninstall-Client.ps1') $out
Copy-Item (Join-Path $root 'README.md'), (Join-Path $root 'CHANGELOG.md') $out
Copy-Item (Join-Path $root '..\LICENSE') $out

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
