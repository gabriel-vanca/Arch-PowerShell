#Requires -RunAsAdministrator

# Script-level switches, forwarded to Install-PowerShellCore by the call at the bottom, so runs from disk
# can pass them. Inert under the documented `irm <url> | iex` path (no way to pass arguments; defaults
# apply), but still valid there: iex compiles the text as a script block, where a leading param block parses.
[CmdletBinding()]
param(
    [switch]$StrictWinget,
    [switch]$ForceUninstallMsix
)

function Install-PowerShellCore {
    <#
    .SYNOPSIS
        Installs PowerShell Core machine-wide from the MSI package on Windows.

    .DESCRIPTION
        Ensures a single, machine-wide MSI install of PowerShell Core is present and
        current. WinGet is preferred; Chocolatey is offered as a fallback whenever the
        WinGet path is unavailable or fails (unless -StrictWinget forbids it). Any
        per-user MSIX install is removed first so the machine does not carry two parallel
        PowerShell Core installs. After installing, the leftover Windows PowerShell 5.1
        "Run with PowerShell" context-menu entry is removed so .ps1 files offer only the
        PowerShell 7 verb, the session PATH is refreshed, and the resulting pwsh.exe is
        executed to confirm the install runs.

    .PARAMETER StrictWinget
        Use WinGet only. When WinGet is absent or its install fails, the function throws
        instead of offering the Chocolatey fallback.

    .PARAMETER ForceUninstallMsix
        Remove any detected per-user MSIX install without prompting for confirmation.

    .NOTES
        #Requires -RunAsAdministrator only fires when this file is run directly from
        disk. The documented install path is `irm <url> | iex`, which never loads it as
        a file, so the directive is inert there and the runtime Assert-Administrator check
        is what actually enforces elevation. See OnlineScriptLoad.MD.

        PowerShell Core is installed machine-wide from the MSI package exclusively. The
        profile step of this repo writes to $PROFILE.AllUsersCurrentHost, which lives in
        $PSHOME and must be writable; the per-user MSIX package's $PSHOME is read-only.
        (AllUsers modules are unaffected: they install to Program Files\PowerShell\Modules,
        not $PSHOME.) Accepted tradeoff: once a release no longer ships an MSI (7.7.0
        onwards), installs stay on the newest release that does, never below 7.6.0.
    #>
    [CmdletBinding()]
    param(
        [switch]$StrictWinget,
        [switch]$ForceUninstallMsix
    )

    # ---- Internal helpers, in the order the main flow uses them ---------------

    function Assert-Administrator {
        Write-Host 'Checking for administrator privileges...' -ForegroundColor Yellow
        $isAdministrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdministrator) {
            Write-Host 'Not running with administrator privileges.' -ForegroundColor Red
            throw 'PowerShell Core is to be installed machine-wide and requires elevation. Restart PowerShell as Administrator and run this script again.'
        }
        Write-Host 'Running with administrator privileges.' -ForegroundColor Green
    }

    # One consent path for both confirmations below, owning all three outcomes: -Force answers yes
    # immediately (printing $ForceNotice), otherwise it prompts only when a user can answer:
    # IsInputRedirected covers piped stdin, and -NonInteractive hosts throw on Read-Host,
    # which the catch converts to the same forced-yes path.
    function Get-UserConsent {
        param([string]$Prompt, [string]$NonInteractiveNotice, [switch]$Force, [string]$ForceNotice)

        if ($Force) {
            Write-Host $ForceNotice -ForegroundColor DarkYellow
            return $true
        }
        if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
            try {
                return ((Read-Host -Prompt $Prompt -ErrorAction Stop) -match '^\s*(y|yes)\s*$')
            }
            catch { }
        }
        Write-Host $NonInteractiveNotice -ForegroundColor DarkYellow
        return $true
    }

    # Versions are matched by shape, so this survives localized winget. Stderr is left un-redirected:
    # under Windows PowerShell 5.1 a redirect wraps native stderr in ErrorRecords (no Trim, and with an
    # inherited $ErrorActionPreference = 'Stop' they throw). Sort explicitly: winget's order is undocumented.
    function Get-AvailablePowerShellVersions {
        $versionLines = & winget show --exact --id Microsoft.PowerShell --source winget --versions --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet failed to list the available PowerShell Core versions (exit code 0x$('{0:X}' -f $LASTEXITCODE))."
        }
        $versionLines |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^\d+\.\d+\.\d+(\.\d+)?$' } |
            Sort-Object { [version]$_ } -Descending
    }

    # -UseWindowsPowerShell (the PS7 compatibility-layer import for this Windows-only module) exists only
    # on 7; 5.1 gets a plain import.
    function Import-AppxModule {
        if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
            return
        }
        try {
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop
            }
            else {
                Import-Module Appx -WarningAction SilentlyContinue -ErrorAction Stop
            }
        }
        catch {
            throw "The Appx module could not be loaded, so existing MSIX installs of PowerShell Core cannot be detected: $($_.Exception.Message)"
        }
    }

    # Removes any per-user MSIX install so the machine does not carry two parallel PowerShell Core installs.
    function Remove-PowerShellMsixPackage {
        param([string]$Pwsh_LatestAvailableVersion, [switch]$ForceUninstallMsix)

        Write-Host 'Checking for a per-user MSIX install of PowerShell Core...' -ForegroundColor Yellow
        Import-AppxModule
        # Get-AppxPackage only enumerates the Appx/MSIX store; an MSI install registers no Appx package and
        # is invisible to it, so this list is MSIX-only.
        $MSIX_InstalledPackages = @(Get-AppxPackage -Name 'Microsoft.PowerShell' -AllUsers -ErrorAction SilentlyContinue)
        if ($MSIX_InstalledPackages.Count -eq 0) {
            Write-Host 'No MSIX install of PowerShell Core found.' -ForegroundColor Green
            return
        }

        # Removing the package hosting the running session would delete the interpreter mid-run.
        if ($PSHOME -like "$Env:ProgramFiles\WindowsApps\*") {
            throw 'This session is running from the MSIX package that must be removed. Re-run this script from Windows PowerShell (powershell.exe) instead.'
        }

        Write-Host 'An MSIX install of PowerShell Core was detected:' -ForegroundColor DarkYellow
        foreach ($MSIX_InstalledPackage in $MSIX_InstalledPackages) {
            Write-Host "  $($MSIX_InstalledPackage.PackageFullName)" -ForegroundColor DarkYellow
        }
        Write-Host 'Removing it (for all users) avoids two parallel installs; new sessions resolve the machine-wide MSI first regardless.' -ForegroundColor Yellow

        # Newest installed MSIX drives the downgrade warning. The replacement MSI version is only decided
        # later (Install-PowerShellMsiViaWinget probes releases newest-first), so $Pwsh_LatestAvailableVersion
        # is only an upper bound: a downgrade is certain only when even that bound already trails the MSIX.
        # Pad both sides to four components before comparing: MSIX identity versions are 4-part (7.6.0.0)
        # while winget lists 3-part (7.6.0), and .NET treats a missing revision as -1, so the raw cast
        # would call equal versions a downgrade.
        function ConvertTo-PaddedVersion {
            param([string]$VersionString)
            $parsed = [version]$VersionString
            [version]::new($parsed.Major, $parsed.Minor, [Math]::Max($parsed.Build, 0), [Math]::Max($parsed.Revision, 0))
        }
        $MSIX_LatestInstalledVersion = $MSIX_InstalledPackages.Version | Sort-Object { [version]$_ } -Descending | Select-Object -First 1
        if ($MSIX_LatestInstalledVersion) {
            if ($Pwsh_LatestAvailableVersion -and (ConvertTo-PaddedVersion $MSIX_LatestInstalledVersion) -gt (ConvertTo-PaddedVersion $Pwsh_LatestAvailableVersion)) {
                Write-Host "WARNING: the installed MSIX ($MSIX_LatestInstalledVersion) is newer than the newest release WinGet offers ($Pwsh_LatestAvailableVersion). Continuing will downgrade PowerShell Core." -ForegroundColor Red
            }
            else {
                Write-Host "The replacement MSI may be an older release than the installed MSIX ($MSIX_LatestInstalledVersion), because the newest releases no longer ship an MSI." -ForegroundColor DarkYellow
            }
        }

        $consentArguments = @{
            Prompt               = 'Remove the MSIX install of PowerShell Core? [y/N]'
            NonInteractiveNotice = 'Non-interactive session: removing the MSIX install without confirmation.'
            Force                = $ForceUninstallMsix
            ForceNotice          = '-ForceUninstallMsix specified: removing the MSIX install without confirmation.'
        }
        if (-not (Get-UserConsent @consentArguments)) {
            throw 'Installation cancelled. The existing MSIX install was left untouched.'
        }

        foreach ($MSIX_InstalledPackage in $MSIX_InstalledPackages) {
            Write-Host "Removing $($MSIX_InstalledPackage.PackageFullName)..." -ForegroundColor Yellow
            try {
                Remove-AppxPackage -Package $MSIX_InstalledPackage.PackageFullName -AllUsers -ErrorAction Stop
            }
            catch {
                throw "Failed to remove MSIX package $($MSIX_InstalledPackage.PackageFullName): $($_.Exception.Message)"
            }
        }
        Write-Host 'MSIX install of PowerShell Core removed.' -ForegroundColor Green
    }

    # Dead MSIX execution-alias stubs are zero-byte files reporting version 0.0.0.0; -All looks past them
    # when a real pwsh sits further down the PATH.
    function Get-InstalledPwshCommand {
        Get-Command pwsh -All -ErrorAction SilentlyContinue |
            Where-Object { $_.Version -and $_.Version -ne [version]'0.0.0.0' } |
            Select-Object -First 1
    }

    # Maps a winget exit code to a result. Returns $true when a restart is still pending, $false on plain
    # success, throws otherwise. Routing is on exit codes only: winget's stdout is localized.
    function Resolve-WingetInstallResult {
        param([int]$ExitCode)

        # 0x8A150109 = restart required to finish; 0x8A15010B = restart initiated.
        if (@(0x8A150109, 0x8A15010B) -contains $ExitCode) {
            return $true
        }
        # 0 = installed; 0x8A150061 / 0x8A15010D = already installed; 0x8A15002B = no applicable update.
        if (@(0, 0x8A150061, 0x8A15002B, 0x8A15010D) -contains $ExitCode) {
            return $false
        }
        throw "WinGet failed to install PowerShell Core (exit code 0x$('{0:X}' -f $ExitCode))."
    }

    # Runs one winget MSI install attempt and returns winget's exit code. $Version pins a release; empty
    # takes the latest (the --version array is splatted, so an empty array adds nothing).
    function Invoke-WingetMsiInstallAttempt {
        param([string]$Version, [string]$InstallParameters)

        $versionArgument = if ($Version) { '--version', $Version } else { @() }

        Write-Host "`n---- WinGet output begins ----" -ForegroundColor Magenta
        Write-Host ''
        # --installer-type wix forces the machine-wide WiX MSI; without it winget defaults to the per-user
        # MSIX (as it has for PowerShell since 7.6.0). Out-Host keeps winget's output on screen without
        # folding it into the return value.
        & winget `
            install `
            --exact `
            --id Microsoft.PowerShell `
            --source winget `
            --installer-type wix `
            --scope machine `
            --disable-interactivity `
            --accept-source-agreements `
            --accept-package-agreements `
            --custom $InstallParameters `
            @versionArgument |
            Out-Host
        Write-Host "`n---- WinGet output ends ----" -ForegroundColor Magenta
        Write-Host ''
        return $LASTEXITCODE
    }

    # Installs the MSI via winget. The first attempt is unpinned (latest); when the newest release ships no
    # MSI (7.7.0 dropped it), earlier releases are pinned and tried newest-first, never below 7.6.0. Returns
    # $true when a restart is still pending.
    function Install-PowerShellMsiViaWinget {
        param([string[]]$AvailableVersions, [string]$InstallParameters)

        # 0x8A150010 = no applicable installer: the release exists but ships no MSI for this request.
        $noApplicableInstaller = 0x8A150010

        Write-Host 'Installing PowerShell Core via WinGet' -ForegroundColor Yellow
        Write-Host "The download URL WinGet prints points to github.com/PowerShell/PowerShell, PowerShell's official release channel. WinGet verifies the installer hash before installing." -ForegroundColor Yellow

        # First attempt is unpinned (latest release).
        $exitCode = Invoke-WingetMsiInstallAttempt -Version '' -InstallParameters $InstallParameters
        if ($exitCode -ne $noApplicableInstaller) {
            return (Resolve-WingetInstallResult -ExitCode $exitCode)
        }

        # The latest release ships no MSI (7.7.0 dropped it). Try earlier releases at or above 7.6.0,
        # newest-first. $AvailableVersions is already sorted descending, so a plain filter preserves order.
        $fallbackVersions = @($AvailableVersions | Select-Object -Skip 1 | Where-Object { [version]$_ -ge [version]'7.6.0' })
        if ($fallbackVersions.Count -eq 0) {
            # The version query earlier returned nothing, so there is no fallback list to try: report that
            # rather than claiming no release ships an MSI.
            throw 'WinGet reported no applicable MSI installer for the latest PowerShell Core, and no version list was available to try earlier releases. PowerShell Core installation cannot continue.'
        }

        Write-Host 'The latest PowerShell Core release no longer ships an MSI package.' -ForegroundColor DarkYellow
        Write-Host 'Trying earlier releases, newest first, not going below 7.6.0...' -ForegroundColor Yellow
        foreach ($version in $fallbackVersions) {
            Write-Host "Trying PowerShell Core $version..." -ForegroundColor Yellow
            $exitCode = Invoke-WingetMsiInstallAttempt -Version $version -InstallParameters $InstallParameters
            if ($exitCode -ne $noApplicableInstaller) {
                return (Resolve-WingetInstallResult -ExitCode $exitCode)
            }
        }
        throw 'No PowerShell Core release at or above 7.6.0 provides an MSI package via WinGet. PowerShell Core installation cannot continue.'
    }

    # Offers the Chocolatey fallback: reports why winget is unavailable, requires choco.exe to be present,
    # and asks the user to confirm. Throws if choco is absent or the user declines.
    function Confirm-ChocolateyFallback {
        param([string]$ChocoExePath, [string]$WingetFailureReason)

        Write-Host "Falling back to Chocolatey: $WingetFailureReason" -ForegroundColor DarkYellow
        if (-not (Test-Path $ChocoExePath)) {
            # Red, not DarkMagenta: the legacy console maps DarkMagenta to its blue background.
            Write-Host 'Chocolatey is not present either.' -ForegroundColor Red
            throw 'Neither WinGet nor Chocolatey can install PowerShell Core. Installation cannot continue.'
        }
        Write-Host 'Chocolatey is present.' -ForegroundColor Green
        if (-not (Get-UserConsent -Prompt 'Install PowerShell Core via Chocolatey? [y/N]' -NonInteractiveNotice 'Non-interactive session: proceeding with the Chocolatey install without confirmation.')) {
            throw 'Installation cancelled. The Chocolatey fallback was declined.'
        }
    }

    # Installs the MSI via Chocolatey. Returns $true when a restart is still pending. Routing is on exit
    # codes only.
    function Install-PowerShellMsiViaChocolatey {
        param([string]$ChocoExePath, [string]$InstallParameters)

        Write-Host 'Installing PowerShell Core via Chocolatey' -ForegroundColor Yellow
        Write-Host "The Chocolatey package downloads PowerShell's MSI from its official release channel (github.com/PowerShell/PowerShell) and verifies its checksum before installing." -ForegroundColor Yellow
        Write-Host "`n---- Chocolatey output begins ----" -ForegroundColor Magenta
        Write-Host ''
        # Invoke the verified binary by full path: bare `choco` resolves through the session PATH, which may
        # not yet hold Chocolatey's bin dir, and would fail non-terminating while leaving a stale (often 0)
        # $LASTEXITCODE that masquerades as success. --install-arguments appends our MSI public properties
        # to the package's silent msiexec call (Chocolatey's equivalent of winget's --custom); the outer
        # double / inner single quotes are Chocolatey's own wrapping for a value that contains spaces.
        & $ChocoExePath install powershell-core -y --packageparameters '/CleanUpPath' --install-arguments="'$InstallParameters'" | Out-Host
        $chocoExitCode = $LASTEXITCODE
        Write-Host "`n---- Chocolatey output ends ----" -ForegroundColor Magenta
        Write-Host ''
        if (@(0, 1641, 3010) -notcontains $chocoExitCode) {
            throw "Chocolatey failed to install PowerShell Core (exit code $chocoExitCode)."
        }
        # 1641 / 3010 = installed, reboot pending.
        return (@(1641, 3010) -contains $chocoExitCode)
    }

    # Removes the Windows PowerShell 5.1 "Run with PowerShell" .ps1 context-menu verb so only the PowerShell
    # 7 verb (installed via ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1) remains. Non-fatal: failures warn only.
    function Remove-WindowsPowerShellContextMenuEntry {
        Write-Host 'Removing the Windows PowerShell 5.1 "Run with PowerShell" context-menu entry...' -ForegroundColor Yellow

        # The verb has lived in two machine-wide locations across Windows versions. Guard on the Command
        # value (which invokes WindowsPowerShell\v1.0\powershell.exe), not the display name: the name is a
        # localized MUI resource. Windows servicing can recreate the entry; re-running the installer removes
        # it again.
        $candidateVerbKeys = @(
            'HKLM:\SOFTWARE\Classes\SystemFileAssociations\.ps1\Shell\Windows.PowerShell.Run'  # Windows 11
            'HKLM:\SOFTWARE\Classes\Microsoft.PowerShellScript.1\Shell\0'                       # legacy
        )

        $removedAny = $false
        foreach ($verbKey in $candidateVerbKeys) {
            if (-not (Test-Path -LiteralPath $verbKey)) {
                continue
            }
            $commandKey = Join-Path $verbKey 'Command'
            $commandItem = Get-Item -LiteralPath $commandKey -ErrorAction SilentlyContinue
            $command = if ($commandItem) { $commandItem.GetValue('') } else { $null }
            if ($command -notmatch 'WindowsPowerShell\\v1\.0\\powershell\.exe') {
                Write-Host "  Skipping $verbKey (does not target Windows PowerShell 5.1)." -ForegroundColor DarkYellow
                continue
            }

            # Back up the parent Shell key before deleting, so the change is reversible.
            $parentShellKey = Split-Path -Parent $verbKey
            $backupName = 'ps1-shell-verbs-' + (($verbKey.Split('\')[-2..-1]) -join '-') + '.reg'
            $backupPath = Join-Path $env:TEMP $backupName
            & reg.exe export ($parentShellKey -replace '^HKLM:', 'HKLM') $backupPath /y | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  Could not back up $parentShellKey; leaving the context-menu entry in place." -ForegroundColor Red
                continue
            }
            Write-Host "  Backed up $parentShellKey to $backupPath" -ForegroundColor DarkYellow

            try {
                Remove-Item -LiteralPath $verbKey -Recurse -Force -ErrorAction Stop
                Write-Host "  Removed $verbKey" -ForegroundColor Green
                $removedAny = $true
            }
            catch {
                Write-Host "  Could not remove ${verbKey}: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        if (-not $removedAny) {
            Write-Host 'No Windows PowerShell 5.1 context-menu entry to remove.' -ForegroundColor Green
        }
    }

    # The MSI updates the machine PATH, which this session cannot see. Append any missing persisted
    # (Machine + User) entries so later steps can resolve pwsh; append rather than replace so session-local
    # additions survive.
    function Sync-SessionPathFromRegistry {
        $persistedPathEntries = @(
            [Environment]::GetEnvironmentVariable('Path', 'Machine')
            [Environment]::GetEnvironmentVariable('Path', 'User')
        ) -split ';' | Where-Object { $_ }
        $sessionPathEntries = $env:Path -split ';'
        $missingPathEntries = @($persistedPathEntries |
                Where-Object { $sessionPathEntries -notcontains $_ } |
                Select-Object -Unique)
        if ($missingPathEntries.Count -gt 0) {
            $env:Path = (@($env:Path) + $missingPathEntries) -join ';'
        }
    }

    # Both install routes place the MSI in Program Files\PowerShell\7, checked first; the PATH search is a
    # fallback for nonstandard locations. Resolving a path is not proof the binary runs, so the resolved
    # pwsh is executed to read its real version. Throws when verification fails; a pending restart is
    # reported without throwing.
    function Confirm-PowerShellCoreInstallation {
        param([bool]$RestartPending)

        Write-Host 'Verifying PowerShell Core installation...' -ForegroundColor Yellow
        $pwshPath = Join-Path $Env:ProgramFiles 'PowerShell\7\pwsh.exe'
        if (-not (Test-Path $pwshPath)) {
            $pwshCommand = Get-InstalledPwshCommand
            $pwshPath = if ($pwshCommand) { $pwshCommand.Source } else { $null }
        }

        $installedVersion = $null
        if ($pwshPath) {
            try {
                $installedVersion = & $pwshPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
                if ($LASTEXITCODE -ne 0) {
                    $installedVersion = $null
                }
            }
            catch {
                Write-Host "Executing $pwshPath failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        if ($installedVersion) {
            Write-Host 'PowerShell Core installation successful.' -ForegroundColor Green
            Write-Host "Installed PowerShell Core version: $installedVersion" -ForegroundColor Green
        }
        elseif ($RestartPending) {
            Write-Host 'pwsh cannot be verified yet: the pending system restart must complete the installation first.' -ForegroundColor DarkYellow
            Write-Host 'After restarting, verify by running pwsh.' -ForegroundColor DarkYellow
        }
        else {
            throw 'PowerShell Core installation failed.'
        }
    }

    # ---- Preconditions --------------------------------------------------------

    # $IsWindows does not exist in Windows PowerShell 5.1 (Windows-only), so it is only consulted on Core.
    # This also keeps an inherited Set-StrictMode from tripping over the undefined variable on 5.1.
    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
        throw 'This script installs PowerShell Core on Windows only.'
    }
    Write-Host 'Installing PowerShell Core'

    Assert-Administrator

    # ---- Install flow ---------------------------------------------------------

    # Reported up front as feedback only; the installer still runs below to apply any available update.
    Write-Host 'Checking if PowerShell Core is already installed...' -ForegroundColor Yellow
    $pwshCommand = Get-InstalledPwshCommand
    if ($pwshCommand) {
        Write-Host 'PowerShell Core is already installed.' -ForegroundColor Green
        Write-Host "Current PowerShell Core version: $($pwshCommand.Version.ToString())" -ForegroundColor Green
        Write-Host 'Running the installer anyway to apply any available update.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'PowerShell Core is not yet installed.' -ForegroundColor Yellow
    }

    # Package-manager presence runs before the MSIX removal below: the only prerequisite for removing the
    # MSIX is that WinGet or Chocolatey is present to install the replacement MSI.
    Write-Host 'Checking for WinGet presence...' -ForegroundColor Yellow
    $wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
    # $env:ChocolateyInstall points at relocated installs; fall back to the ProgramData default when unset.
    $chocoInstallRoot = if ($env:ChocolateyInstall) { $env:ChocolateyInstall } else { Join-Path $Env:ProgramData 'chocolatey' }
    $chocoExePath = Join-Path $chocoInstallRoot 'choco.exe'

    $installViaChocolatey = $false
    if ($wingetCommand) {
        Write-Host 'WinGet present' -ForegroundColor Green
    }
    elseif ($StrictWinget) {
        Write-Host 'WinGet missing.' -ForegroundColor Red
        throw '-StrictWinget was specified but WinGet is not present. PowerShell Core installation cannot continue.'
    }
    else {
        Write-Host 'WinGet missing...' -ForegroundColor DarkYellow
        $installViaChocolatey = $true
    }

    # When Chocolatey is already known to be the only install route, its presence check and consent run up
    # front (both inside Confirm-ChocolateyFallback), before the MSIX removal below: declining after the
    # removal would leave no PowerShell Core install at all. The winget-failure fallback can only ask at
    # failure time, which is after the removal.
    if ($installViaChocolatey) {
        Confirm-ChocolateyFallback -ChocoExePath $chocoExePath -WingetFailureReason 'WinGet is not present.'
    }

    # WinGet-only step; best-effort. The list only sharpens the MSIX downgrade warning and feeds the
    # older-release fallback loop. If WinGet is broken enough to fail here, the install attempt below fails
    # too and (default mode) routes to Chocolatey.
    $availableVersions = @()
    if ($wingetCommand) {
        Write-Host 'Querying WinGet for the available PowerShell Core versions (any warnings below come from WinGet)...' -ForegroundColor Yellow
        try {
            $availableVersions = @(Get-AvailablePowerShellVersions)
        }
        catch {
            Write-Host "Could not query WinGet versions: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    # Detection uses -AllUsers, which needs the elevation asserted above.
    Remove-PowerShellMsixPackage -Pwsh_LatestAvailableVersion ($availableVersions | Select-Object -First 1) -ForceUninstallMsix:$ForceUninstallMsix

    # MSI public properties, shared by both install routes. Defaults noted are the package's own.
    $MSI_INSTALL_PARAMETERS = @(
        'ADD_PATH=1'                                   # DEFAULT on  - adds install dir to system PATH (HKLM)
        'REGISTER_MANIFEST=1'                          # DEFAULT on  - registers ETW / Windows event-log manifest
        'USE_MU=1'                                     # DEFAULT on  - opt into Microsoft Update / WSUS servicing
        'ENABLE_MU=1'                                  # DEFAULT on  - enable automatic updates via MU
        'ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1'        # off default - forced ON: "Run with PowerShell 7" on .ps1
        'DISABLE_TELEMETRY=1'                          # off default - forced ON: sets POWERSHELL_TELEMETRY_OPTOUT
        'ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=0'   # off default - forced OFF: Windows Terminal already provides this
        'ENABLE_PSREMOTING=0'                          # off default - forced OFF: no PS remoting endpoint on install
    ) -join ' '

    $restartPending = $false
    if (-not $installViaChocolatey) {
        try {
            $restartPending = Install-PowerShellMsiViaWinget -AvailableVersions $availableVersions -InstallParameters $MSI_INSTALL_PARAMETERS
        }
        catch {
            if ($StrictWinget) {
                throw
            }
            Write-Host "WinGet could not install PowerShell Core: $($_.Exception.Message)" -ForegroundColor Red
            Confirm-ChocolateyFallback -ChocoExePath $chocoExePath -WingetFailureReason $_.Exception.Message
            $installViaChocolatey = $true
        }
    }
    if ($installViaChocolatey) {
        $restartPending = Install-PowerShellMsiViaChocolatey -ChocoExePath $chocoExePath -InstallParameters $MSI_INSTALL_PARAMETERS
    }

    # ---- Post-install: announce restart, remove the PS 5.1 verb, refresh PATH, verify ----
    if ($restartPending) {
        Write-Host 'PowerShell Core installed. A system restart is required to finish the installation.' -ForegroundColor DarkYellow
    }
    Remove-WindowsPowerShellContextMenuEntry
    Sync-SessionPathFromRegistry
    Confirm-PowerShellCoreInstallation -RestartPending $restartPending
}

Install-PowerShellCore @PSBoundParameters
