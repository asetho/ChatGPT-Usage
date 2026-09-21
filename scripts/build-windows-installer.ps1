[CmdletBinding()]
param([switch]$KeepOldPackages)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$version = (Get-Content (Join-Path $repoRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw 'VERSION must use semantic versioning (for example 1.0.1).'
}

$windowsRoot = Join-Path $repoRoot 'Windows'
$payload = Join-Path $windowsRoot 'InstallerPayload'
if (Test-Path -LiteralPath $payload) {
    Remove-Item -LiteralPath $payload -Recurse -Force
}

& (Join-Path $repoRoot 'scripts\generate-windows-icon.ps1') -OutputPath (Join-Path $windowsRoot 'Assets\ChatGPTUsage.ico')

dotnet restore (Join-Path $windowsRoot 'ChatGPTUsage.Windows.csproj') `
    -r win-x64 `
    -p:SelfContained=true `
    --locked-mode
if ($LASTEXITCODE -ne 0) {
    throw "dotnet restore failed with exit code $LASTEXITCODE. Update packages.lock.json before building the installer."
}

dotnet publish (Join-Path $windowsRoot 'ChatGPTUsage.Windows.csproj') `
    -c Release `
    -r win-x64 `
    --self-contained true `
    --no-restore `
    -p:Version=$version `
    -p:FileVersion=$version `
    -p:AssemblyVersion=$version `
    -o $payload
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE. No installer was built."
}
if (!(Test-Path -LiteralPath (Join-Path $payload 'ChatGPTUsage.Windows.exe') -PathType Leaf)) {
    throw 'dotnet publish did not produce ChatGPTUsage.Windows.exe. No installer was built.'
}

$compiler = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($null -eq $compiler) {
    throw 'Inno Setup 6 is required to build the Windows installer.'
}

& $compiler "/DMyAppVersion=$version" (Join-Path $windowsRoot 'Installer.iss')
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$installer = Join-Path $windowsRoot "dist\ChatGPTUsage-Setup-$version.exe"
if (!(Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "The compiler did not produce the expected installer: $installer"
}
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
# Use LF so the checksum file also works with macOS shasum and GNU sha256sum.
[System.IO.File]::WriteAllText("$installer.sha256", "$hash  $(Split-Path -Leaf $installer)`n", [System.Text.Encoding]::ASCII)

if (!$KeepOldPackages) {
    $packages = Get-ChildItem (Join-Path $windowsRoot 'dist') -File -Filter 'ChatGPTUsage-Setup-*.exe' |
        ForEach-Object {
            if ($_.BaseName -match '^ChatGPTUsage-Setup-(\d+\.\d+\.\d+)$') {
                [PSCustomObject]@{ File = $_; Version = [version]$Matches[1] }
            }
        } |
        Sort-Object Version -Descending

    $packages | Select-Object -Skip 3 | ForEach-Object {
        Remove-Item -LiteralPath $_.File.FullName -Force
        $checksum = "$($_.File.FullName).sha256"
        if (Test-Path -LiteralPath $checksum) {
            Remove-Item -LiteralPath $checksum -Force
        }
        Write-Output "Removed old package $($_.File.FullName)"
    }
}

Write-Output "Created $installer"
Write-Output "Created $installer.sha256"
