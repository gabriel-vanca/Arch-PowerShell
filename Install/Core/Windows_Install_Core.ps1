#Requires -RunAsAdministrator

# #R_equires only fires when this file is run directly from disk. The documented install path is
# `irm <url> | iex`, which never loads it as a file, so the directive is inert there and the
# runtime check below is what actually enforces elevation. See OnlineScriptLoad.MD.
#
# PowerShell Core is installed machine-wide from the MSI package exclusively. The profile step of
# this repo writes to $PROFILE.AllUsersCurrentHost, which lives in $PSHOME and must be writable;
# the per-user MSIX package's $PSHOME is read-only. (AllUsers modules are unaffected: they install
# to Program Files\PowerShell\Modules, not $PSHOME.) Accepted tradeoff: once a release no longer
# ships an MSI (7.7.0 onwards), installs stay on the newest release that does, never below 7.6.0.

# $IsWindows does not exist in Windows PowerShell 5.1, so it is $NULL there.
if ($IsWindows -or ($NULL -eq $IsWindows)) {
    Write-Host "Installing PowerShell Core"
}
else {
    throw "Not Windows"
}

# Version numbers are matched by shape, not by field label, so this works on localized winget.
function Get-AvailablePowerShellVersions {
    (& winget show --exact --id Microsoft.PowerShell --source winget --versions --disable-interactivity 2>&1) |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^\d+\.\d+\.\d+(\.\d+)?$' }
}

function Assert-WingetSucceeded {
    param([int]$ExitCode)

    # 0x8A150109 = install succeeded, restart required to finish; 0x8A15010B = restart initiated.
    if (@(0x8A150109, 0x8A15010B) -contains $ExitCode) {
        Write-Host "PowerShell Core installed. A system restart is required to finish the installation."  -ForegroundColor DarkYellow
        return
    }
    # 0x8A150061 / 0x8A15010D = package already installed, 0x8A15002B = no applicable update.
    # All mean PowerShell Core is already present and current, which is a success here.
    if (@(0, 0x8A150061, 0x8A15002B, 0x8A15010D) -contains $ExitCode) {
        return
    }
    throw "WinGet failed to install PowerShell Core (exit code 0x$('{0:X}' -f $ExitCode))."
}

# WinGet has defaulted to the per-user MSIX for PowerShell since 7.6.0, so the MSI is forced here.
# When the newest release no longer ships an MSI (7.7.0 dropped it), earlier releases are tried
# newest-first, never below 7.6.0. Routing is done purely on exit codes: winget's stdout is
# localized and must not be parsed.
function Install-PowerShellMsiViaWinget {
    param([string[]]$AvailableVersions)

    $baseArguments = @(
        'install', '--exact', '--id', 'Microsoft.PowerShell'
        '--accept-source-agreements', '--accept-package-agreements'
        '--source', 'winget', '--disable-interactivity'
        '--installer-type', 'wix'
        '--scope', 'machine'
    )
    # 0x8A150049 = no applicable installer: the release exists but ships no MSI for this request.
    $noApplicableInstaller = 0x8A150049

    Write-Host "Installing PowerShell Core via WinGet" -ForegroundColor DarkYellow
    & winget @baseArguments
    if ($LASTEXITCODE -ne $noApplicableInstaller) {
        Assert-WingetSucceeded -ExitCode $LASTEXITCODE
        return
    }

    Write-Host "The latest PowerShell Core release no longer ships an MSI package."  -ForegroundColor DarkYellow
    Write-Host "Trying earlier releases, newest first, not going below 7.6.0..."  -ForegroundColor DarkYellow
    # The first listed version is the latest, which the attempt above already covered.
    foreach ($version in ($AvailableVersions | Select-Object -Skip 1)) {
        if ([version]$version -lt [version]'7.6.0') {
            break
        }
        Write-Host "Trying PowerShell Core $version..."  -ForegroundColor DarkYellow
        & winget @baseArguments --version $version
        if ($LASTEXITCODE -ne $noApplicableInstaller) {
            Assert-WingetSucceeded -ExitCode $LASTEXITCODE
            return
        }
    }
    throw "No PowerShell Core release at or above 7.6.0 provides an MSI package via WinGet. PowerShell Core installation cannot continue."
}

# Appx is a Windows PowerShell module. PowerShell 7 reaches it through the compatibility layer.
function Import-AppxModule {
    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        return
    }
    Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop
}

# A per-user MSIX install is removed so the machine does not carry two parallel PowerShell Core
# installs (Store auto-updates fighting the MSI, duplicate entries everywhere). Fresh sessions
# would resolve the MSI first regardless: machine PATH entries precede user PATH entries, and the
# MSIX alias lives on the user PATH.
function Remove-PowerShellMsixPackage {
    param([string]$NewestAvailableVersion)

    Write-Host "Checking for a per-user MSIX install of PowerShell Core..."  -ForegroundColor DarkYellow
    Import-AppxModule
    $msixPackages = @(Get-AppxPackage -Name 'Microsoft.PowerShell' -AllUsers -ErrorAction SilentlyContinue)
    if ($msixPackages.Count -eq 0) {
        Write-Host "No MSIX install of PowerShell Core found."  -ForegroundColor DarkGreen
        return
    }

    # Removing the package hosting the running session would delete the interpreter mid-run.
    if ($PSHOME -like "$Env:ProgramFiles\WindowsApps\*") {
        throw "This session is running from the MSIX package that must be removed. Re-run this script from Windows PowerShell (powershell.exe) instead."
    }

    Write-Host "An MSIX install of PowerShell Core was detected:"  -ForegroundColor DarkYellow
    foreach ($msixPackage in $msixPackages) {
        Write-Host "  $($msixPackage.PackageFullName)"  -ForegroundColor DarkYellow
    }
    Write-Host "Removing it avoids two parallel PowerShell Core installs. New sessions would resolve the machine-wide MSI first either way."  -ForegroundColor DarkYellow
    Write-Host "This removes the MSIX package for all users on this machine."  -ForegroundColor DarkRed

    $msixVersion = $msixPackages[0].Version
    if ($NewestAvailableVersion -and $msixVersion -and ([version]$msixVersion -gt [version]$NewestAvailableVersion)) {
        Write-Host "WARNING: the installed MSIX ($msixVersion) is newer than the newest release available via WinGet ($NewestAvailableVersion). Continuing is a downgrade."  -ForegroundColor DarkRed
    }
    elseif ($msixVersion) {
        Write-Host "The MSI install targets the newest release that still ships an MSI package, which may be older than the current MSIX version ($msixVersion)."  -ForegroundColor DarkYellow
    }

    $removalConfirmed = $false
    # Prompt only when a user can actually answer. IsInputRedirected covers piped stdin; hosts
    # started with -NonInteractive refuse Read-Host, which the catch below converts to the same
    # forced path.
    $canPrompt = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if ($canPrompt) {
        try {
            $confirmation = Read-Host -Prompt "Remove the MSIX install of PowerShell Core? [y/N]" -ErrorAction Stop
            $removalConfirmed = $confirmation -match '^\s*(y|yes)\s*$'
        }
        catch {
            $canPrompt = $false
        }
    }
    if (-not $canPrompt) {
        Write-Host "Non-interactive session: removing the MSIX install without confirmation."  -ForegroundColor DarkYellow
        $removalConfirmed = $true
    }
    if (-not $removalConfirmed) {
        throw "Installation cancelled. The existing MSIX install was left untouched."
    }

    foreach ($msixPackage in $msixPackages) {
        Write-Host "Removing $($msixPackage.PackageFullName)..."  -ForegroundColor DarkYellow
        Remove-AppxPackage -Package $msixPackage.PackageFullName -AllUsers -ErrorAction Stop
    }
    Write-Host "MSIX install of PowerShell Core removed."  -ForegroundColor DarkGreen
}

Write-Host "Checking for administrator privileges..."  -ForegroundColor DarkYellow
$isAdministrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdministrator) {
    Write-Host "Not running with administrator privileges."  -ForegroundColor DarkRed
    throw "PowerShell Core is installed machine-wide and requires elevation. Restart PowerShell as Administrator and run this script again."
}
Write-Host "Running with administrator privileges." -ForegroundColor DarkGreen

# The package-manager check runs before the MSIX removal below, so removal can never leave the
# machine without a way to install the replacement MSI.
Write-Host "Checking for WinGet presence..."  -ForegroundColor DarkYellow
$wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
# Expected path of the choco.exe file.
$chocoInstallPath = "$Env:ProgramData/chocolatey/choco.exe"
if ($wingetCommand) {
    Write-Host "WinGet present" -ForegroundColor DarkGreen
}
else {
    Write-Host "WinGet missing..."  -ForegroundColor DarkYellow
    Write-Host "Checking for Chocolatey presence..."  -ForegroundColor DarkYellow
    Start-Sleep 10
    if (Test-Path "$chocoInstallPath") {
        Write-Host "Chocolatey is present."  -ForegroundColor DarkGreen
    }
    else {
        Write-Host "Chocolatey is missing."  -ForegroundColor DarkMagenta
        throw "Neither Winget nor Chocolatey present. PowerShell Core installation cannot continue."
    }
}

$availableVersions = @()
if ($wingetCommand) {
    $availableVersions = @(Get-AvailablePowerShellVersions)
}

# Detection uses -AllUsers, which needs the elevation asserted above.
Remove-PowerShellMsixPackage -NewestAvailableVersion ($availableVersions | Select-Object -First 1)

Write-Host "Checking if PowerShell Core is already installed..."  -ForegroundColor DarkYellow

$pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pwshCommand) {
    Write-Host "PowerShell Core is already installed." -ForegroundColor DarkGreen
    Write-Host "Current PowerShell Core version: $($pwshCommand.Version.ToString())" -ForegroundColor DarkGreen
    Write-Host "Running the installer anyway to apply any available update."  -ForegroundColor DarkYellow
}
else {
    Write-Host "PowerShell Core is not yet installed."  -ForegroundColor DarkYellow
}

if ($wingetCommand) {
    Install-PowerShellMsiViaWinget -AvailableVersions $availableVersions
}
else {
    Write-Host "Installing PowerShell Core via Chocolatey" -ForegroundColor DarkYellow
    choco install powershell-core -y --packageparameters '"/CleanUpPath"'
    $chocoExitCode = $LASTEXITCODE
    # 1641 and 3010 mean the install succeeded and a reboot is pending.
    if (@(0, 1641, 3010) -notcontains $chocoExitCode) {
        throw "Chocolatey failed to install PowerShell Core (exit code $chocoExitCode)."
    }
}

# The MSI installs to C:\Program Files\PowerShell\7 and updates the machine PATH, which this
# session cannot see. Add any missing entries so later steps in this session can resolve pwsh.
# Entries are appended rather than replaced so session-local PATH additions survive.
$registryPath = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine')
    [Environment]::GetEnvironmentVariable('Path', 'User')
) -join ';'
foreach ($pathEntry in ($registryPath -split ';' | Where-Object { $_ })) {
    if (($env:Path -split ';') -notcontains $pathEntry) {
        $env:Path += ";$pathEntry"
    }
}

Write-Host "Verifying PowerShell Core installation..."  -ForegroundColor DarkYellow
# Both install routes place the MSI in Program Files\PowerShell\7, so that exact path is checked
# first. The PATH search is only a fallback for nonstandard install locations, and dead app
# execution alias stubs (zero-byte files reporting version 0.0.0.0) are rejected.
$pwshPath = Join-Path $Env:ProgramFiles 'PowerShell\7\pwsh.exe'
if (-not (Test-Path $pwshPath)) {
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue |
        Where-Object { $_.Version -and $_.Version -ne [version]'0.0.0.0' } |
        Select-Object -First 1
    $pwshPath = if ($pwshCommand) { $pwshCommand.Source } else { $NULL }
}

$installedVersion = $NULL
if ($pwshPath) {
    # Resolving a path is not proof the binary runs; execute it and read the real version.
    $installedVersion = & $pwshPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
}
if ($installedVersion -and $LASTEXITCODE -eq 0) {
    Write-Host "PowerShell Core installation successful." -ForegroundColor DarkGreen
    Write-Host "Installed PowerShell Core version: $installedVersion" -ForegroundColor DarkGreen
    return "PowerShell Core installation successful."
}
else {
    Write-Host "PowerShell Core installation failed."  -ForegroundColor DarkRed
    throw "PowerShell Core installation failed."
}
