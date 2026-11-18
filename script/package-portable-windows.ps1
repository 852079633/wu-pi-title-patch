[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('x86_64')]
    [string]$Architecture,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ExpectedCommit
)

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bundle = Join-Path $workspace "inno\$Architecture"
$target = Join-Path $workspace 'target'
$portable = Join-Path $target "wu-portable-$Architecture"

$sourceCommit = (& git -C $workspace rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not read source commit.' }
if ($sourceCommit -ne $ExpectedCommit) {
    throw "Build source does not match tested commit. Expected $ExpectedCommit, got $sourceCommit"
}

if (-not (Test-Path -LiteralPath $bundle -PathType Container)) {
    throw "Wu bundler output is missing: $bundle"
}
$requiredBundleFiles = @(
    'Wu.exe',
    'conpty.dll',
    'amd_ags_x64.dll',
    'x64\OpenConsole.exe',
    'arm64\OpenConsole.exe',
    'bin\wu.exe',
    'bin\wu',
    'tools\auto_update_helper.exe',
    'appx\zed_explorer_command_injector.appx',
    'appx\zed_explorer_command_injector.dll',
    'file_icons\document.ico'
)
foreach ($relativePath in $requiredBundleFiles) {
    $sourcePath = Join-Path $bundle $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Required Wu runtime file is missing: $sourcePath"
    }
}

$requiredLicenseFiles = @('LICENSE-GPL', 'LICENSE-APACHE', 'assets\licenses.md', 'THIRD_PARTY_NOTICES.md')
foreach ($relativePath in $requiredLicenseFiles) {
    $licensePath = Join-Path $workspace $relativePath
    if (-not (Test-Path -LiteralPath $licensePath -PathType Leaf)) {
        throw "Required license material is missing: $licensePath"
    }
}

if (Test-Path -LiteralPath $portable) {
    throw "Refusing to overwrite an existing staging directory: $portable"
}
New-Item -Path $portable -ItemType Directory -Force | Out-Null

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Destination $_.Name) -Recurse -Force
    }
}

Copy-Item -LiteralPath (Join-Path $bundle 'Wu.exe') -Destination $portable
Copy-Item -LiteralPath (Join-Path $bundle 'conpty.dll') -Destination $portable
Copy-Item -LiteralPath (Join-Path $bundle 'amd_ags_x64.dll') -Destination $portable
Copy-DirectoryContents -Source (Join-Path $bundle 'bin') -Destination (Join-Path $portable 'bin')
Copy-DirectoryContents -Source (Join-Path $bundle 'tools') -Destination (Join-Path $portable 'tools')
Copy-DirectoryContents -Source (Join-Path $bundle 'appx') -Destination (Join-Path $portable 'appx')
Copy-DirectoryContents -Source (Join-Path $bundle 'x64') -Destination (Join-Path $portable 'x64')
Copy-DirectoryContents -Source (Join-Path $bundle 'arm64') -Destination (Join-Path $portable 'arm64')
Copy-DirectoryContents -Source (Join-Path $bundle 'file_icons') -Destination (Join-Path $portable 'resources\file_icons')
Copy-Item -LiteralPath (Join-Path $workspace 'LICENSE-GPL') -Destination $portable
Copy-Item -LiteralPath (Join-Path $workspace 'LICENSE-APACHE') -Destination $portable
Copy-Item -LiteralPath (Join-Path $workspace 'THIRD_PARTY_NOTICES.md') -Destination $portable
New-Item -Path (Join-Path $portable 'assets') -ItemType Directory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $workspace 'assets\licenses.md') -Destination (Join-Path $portable 'assets\licenses.md')

$requiredPortableFiles = @(
    'Wu.exe',
    'conpty.dll',
    'amd_ags_x64.dll',
    'x64\OpenConsole.exe',
    'arm64\OpenConsole.exe',
    'bin\wu.exe',
    'bin\wu',
    'tools\auto_update_helper.exe',
    'appx\zed_explorer_command_injector.appx',
    'appx\zed_explorer_command_injector.dll',
    'resources\file_icons\document.ico',
    'LICENSE-GPL',
    'LICENSE-APACHE',
    'THIRD_PARTY_NOTICES.md',
    'assets\licenses.md'
)
foreach ($relativePath in $requiredPortableFiles) {
    $portablePath = Join-Path $portable $relativePath
    if (-not (Test-Path -LiteralPath $portablePath -PathType Leaf)) {
        throw "Portable runtime is incomplete: $portablePath"
    }
}

$crateManifest = Join-Path $workspace 'crates\wu\Cargo.toml'
$versionMatch = Select-String -LiteralPath $crateManifest -Pattern '^version = "([^\"]+)"' | Select-Object -First 1
if (-not $versionMatch) { throw "Could not read Wu version from $crateManifest" }
$version = $versionMatch.Matches[0].Groups[1].Value
$toolchainPath = Join-Path $workspace 'rust-toolchain.toml'
$toolchainMatch = Select-String -LiteralPath $toolchainPath -Pattern '^channel = "([^\"]+)"' | Select-Object -First 1
if (-not $toolchainMatch) { throw "Could not read Rust toolchain from $toolchainPath" }
$rustToolchain = $toolchainMatch.Matches[0].Groups[1].Value

$zipName = "Wu-$version-$Architecture-portable.zip"
$zipPath = Join-Path $target $zipName
$metadataPath = Join-Path $target "Wu-$version-$Architecture-portable.json"
if ((Test-Path -LiteralPath $zipPath) -or (Test-Path -LiteralPath $metadataPath)) {
    throw 'Refusing to overwrite an existing portable artifact.'
}
New-Item -Path $target -ItemType Directory -Force | Out-Null
Compress-Archive -Path (Join-Path $portable '*') -DestinationPath $zipPath -CompressionLevel Optimal

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    foreach ($relativePath in $requiredPortableFiles) {
        $zipPathEntry = $relativePath.Replace('\', '/')
        if ($entries -notcontains $zipPathEntry) {
            throw "Portable ZIP is missing required entry: $zipPathEntry"
        }
    }
} finally {
    $archive.Dispose()
}

$sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$serverUrl = if ($env:GITHUB_SERVER_URL) { $env:GITHUB_SERVER_URL.TrimEnd('/') } else { 'https://github.com' }
$repository = if ($env:GITHUB_REPOSITORY) { $env:GITHUB_REPOSITORY } else { '852079633/wu-pi-title-patch' }
$repositoryUrl = "$serverUrl/$repository"
$workflowRunUrl = $null
if ($env:GITHUB_RUN_ID) { $workflowRunUrl = "$repositoryUrl/actions/runs/$env:GITHUB_RUN_ID" }
$runnerImage = if ($env:WU_RUNNER_IMAGE) { $env:WU_RUNNER_IMAGE } elseif ($env:RUNNER_OS) { $env:RUNNER_OS } else { 'Windows (local)' }
$metadata = [ordered]@{
    product = 'Wu unofficial Pi terminal-tab title patch'
    version = $version
    architecture = $Architecture
    release_channel = 'stable'
    source_repository = $repositoryUrl
    source_commit = $sourceCommit
    tested_source_commit = $ExpectedCommit
    source_commit_url = "$repositoryUrl/commit/$sourceCommit"
    workflow_file = '.github/workflows/pi-title-patch.yml'
    workflow_run_id = $env:GITHUB_RUN_ID
    workflow_run_attempt = $env:GITHUB_RUN_ATTEMPT
    workflow_run_url = $workflowRunUrl
    runner_image = $runnerImage
    rust_toolchain = $rustToolchain
    cargo_build_jobs = 2
    build_command = 'Set RELEASE_CHANNEL=stable; use Rust 1.97.1; initialize MSVC; run script/bundle-windows.ps1 -Architecture x86_64 with --locked Cargo builds'
    artifact = $zipName
    sha256 = $sha256
    included_license_material = @('LICENSE-GPL', 'LICENSE-APACHE', 'assets/licenses.md', 'THIRD_PARTY_NOTICES.md')
    installation_performed = $false
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding utf8
Write-Output "PORTABLE_ZIP=$zipPath"
Write-Output "METADATA=$metadataPath"
Write-Output "SOURCE_COMMIT=$sourceCommit"
Write-Output "SHA256=$sha256"
Write-Output 'REQUIRED_RUNTIME_LAYOUT=PASS'
Write-Output 'LICENSE_MATERIAL=PASS'
Write-Output 'INSTALLATION_PERFORMED=False'
