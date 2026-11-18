$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'This helper is restricted to an ephemeral GitHub Actions workspace.'
}

$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseChannel = Join-Path $workspace 'crates\wu\RELEASE_CHANNEL'
[System.IO.File]::WriteAllText($releaseChannel, 'stable', [System.Text.Encoding]::ASCII)

& (Join-Path $PSScriptRoot 'bundle-windows.ps1') -Architecture x86_64
