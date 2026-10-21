param([Parameter(Mandatory)][string]$ManifestPath)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$request = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$executable = Join-Path $request.InstallDirectory 'ChatGPTUsage.Windows.exe'
try {
    $installed = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{85D35CB7-34B0-4D09-9E6F-8E4AE03AFAFA}_is1').InstallLocation
    if ([IO.Path]::GetFullPath($installed).TrimEnd('\') -ne [IO.Path]::GetFullPath($request.InstallDirectory).TrimEnd('\')) {
        throw 'The installed location changed. Nothing was installed.'
    }
    if ((Get-FileHash -LiteralPath $request.Installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne $request.Sha256) {
        throw 'The update checksum changed. Nothing was installed.'
    }
    [IO.File]::WriteAllText((Join-Path $request.Transaction 'ready'), '')
    $parentProcess = Get-Process -Id $request.ParentId -ErrorAction SilentlyContinue
    if ($null -ne $parentProcess -and $parentProcess.StartTime.ToUniversalTime().Ticks.ToString() -eq $request.ParentStartTicks) {
        if (!$parentProcess.WaitForExit(60000)) { throw 'The app did not close, so the update was not installed.' }
    }
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/NOCLOSEAPPLICATIONS', '/NORESTARTAPPLICATIONS', '/COMPANIONUPDATE=1',
        ('/DIR="' + $request.InstallDirectory + '"'), ('/LOG="' + (Join-Path $request.Transaction 'install.log') + '"'))
    $installer = Start-Process -FilePath $request.Installer -ArgumentList $arguments -Wait -PassThru
    if ($installer.ExitCode -ne 0) { throw "The installer exited with code $($installer.ExitCode)." }
    $found = (Get-Item -LiteralPath $executable).VersionInfo
    $version = '{0}.{1}.{2}' -f $found.FileMajorPart, $found.FileMinorPart, $found.FileBuildPart
    if ($version -ne $request.Version) { throw 'The installed version does not match the update.' }
    Start-Process -FilePath $executable | Out-Null
    # Retain only the small install log; the downloaded executable is no longer needed.
    Remove-Item -LiteralPath $request.Installer -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $request.ErrorPath -Force -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText((Join-Path $request.Transaction 'completed'), $version)
} catch {
    [IO.File]::WriteAllText($request.ErrorPath, 'The update could not finish. Try again or use View release to install it manually.')
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $request.Transaction 'error-detail.txt')
    # The installer handles its own rollback. Reopen whichever installed version remains usable.
    if (Test-Path -LiteralPath $executable) { Start-Process -FilePath $executable -ErrorAction SilentlyContinue | Out-Null }
    exit 1
}
