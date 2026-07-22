#Requires -RunAsAdministrator

function Install-PowerShellCore {
    <#
    .SYNOPSIS
        Installs PowerShell Core machine-wide from the MSI package on Windows.

    .DESCRIPTION
        Ensures a single, machine-wide MSI install of PowerShell Core is present and
        current. WinGet is preferred; Chocolatey is the fallback when WinGet is absent.
        Any per-user MSIX install is removed first so the machine does not carry two
        parallel PowerShell Core installs. After installing, the session PATH is
        refreshed and the resulting pwsh.exe is executed to confirm the install runs.

    .NOTES
        #Requires -RunAsAdministrator only fires when this file is run directly from
        disk. The documented install path is `irm <url> | iex`, which never loads it as
        a file, so the directive is inert there and the runtime elevation check below is
        what actually enforces elevation. See OnlineScriptLoad.MD.

        PowerShell Core is installed machine-wide from the MSI package exclusively. The
        profile step of this repo writes to $PROFILE.AllUsersCurrentHost, which lives in
        $PSHOME and must be writable; the per-user MSIX package's $PSHOME is read-only.
        (AllUsers modules are unaffected: they install to Program Files\PowerShell\Modules,
        not $PSHOME.) Accepted tradeoff: once a release no longer ships an MSI (7.7.0
        onwards), installs stay on the newest release that does, never below 7.6.0.
    #>
    [CmdletBinding()]
    param()

    begin {
        # ---- Internal helpers, in the order the main flow uses them -----------

        # The #Requires directive at the top only fires when this file is run from disk; the documented
        # `irm <url> | iex` path never loads it as a file, so this runtime check is what actually enforces
        # elevation. The machine-wide MSI install and the -AllUsers Appx detection below both need it.
        function Assert-Administrator {
            Write-Host 'Checking for administrator privileges...' -ForegroundColor Yellow
            $isAdministrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdministrator) {
                Write-Host 'Not running with administrator privileges.' -ForegroundColor Red
                throw 'PowerShell Core is to be installed machine-wide and requires elevation.
        Restart PowerShell as Administrator and run this script again.'
            }
            Write-Host 'Running with administrator privileges.' -ForegroundColor Green
        }

        # Version numbers are matched by shape, not by field label, so this works on localized winget.
        # Stderr is deliberately not redirected: under Windows PowerShell 5.1 a redirect wraps native
        # stderr lines in ErrorRecords (which have no Trim method and, with an inherited
        # $ErrorActionPreference = 'Stop', throw NativeCommandError). The version list is sorted
        # explicitly because winget's output order is undocumented CLI behavior.
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

        # Appx is a Windows PowerShell module. PowerShell 7 reaches it through the compatibility layer;
        # -UseWindowsPowerShell only exists there, so 5.1 gets a plain import.
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

        # A per-user MSIX install is removed so the machine does not carry two parallel PowerShell Core
        # installs (Store auto-updates fighting the MSI, duplicate entries everywhere). Fresh sessions
        # would resolve the MSI first regardless: machine PATH entries precede user PATH entries, and the
        # MSIX alias lives on the user PATH.
        function Remove-PowerShellMsixPackage {
            param([string]$Pwsh_LatestAvailableVersion)

            Write-Host 'Checking for a per-user MSIX install of PowerShell Core...' -ForegroundColor Yellow
            Import-AppxModule
            # Get-AppxPackage only ever enumerates the Appx/MSIX deployment store (Store apps and
            # sideloaded .msix/.appx); an MSI install of PowerShell registers no Appx package and is
            # invisible to it, so this list is MSIX-only.
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
            Write-Host 'Removing it avoids two parallel PowerShell Core installs. New sessions would resolve the machine-wide MSI first either way.' -ForegroundColor Yellow
            Write-Host 'This removes the MSIX package for all users on this machine.' -ForegroundColor Red

            # Multiple packages are possible (e.g. per-architecture); the newest one drives the warning.
            $MSIX_LatestInstalledVersion = $MSIX_InstalledPackages.Version |
                Sort-Object { [version]$_ } -Descending | Select-Object -First 1

            # Which release's MSI actually lands is only decided later, by Install-PowerShellMsiViaWinget
            # probing releases newest-first and taking the first that still ships an MSI (7.7.0 onwards
            # ship none). So the exact replacement version is unknown here; $Pwsh_LatestAvailableVersion
            # (the newest release WinGet lists, MSI or not) is only an upper bound on what lands. We can
            # therefore state a downgrade with certainty only when even that upper bound already trails
            # the installed MSIX; otherwise we can merely flag the risk.
            if ($MSIX_LatestInstalledVersion) {
                if ($Pwsh_LatestAvailableVersion -and [version]$MSIX_LatestInstalledVersion -gt [version]$Pwsh_LatestAvailableVersion) {
                    # Even the newest release WinGet offers is older than the MSIX: a downgrade is certain.
                    Write-Host "WARNING: the installed MSIX ($MSIX_LatestInstalledVersion) is newer than the newest release WinGet offers ($Pwsh_LatestAvailableVersion). Continuing will downgrade PowerShell Core." -ForegroundColor Red
                }
                else {
                    # A new enough release exists, but the MSI fallback may resolve to an older one.
                    Write-Host "The replacement MSI may be an older release than the installed MSIX ($MSIX_LatestInstalledVersion), because the newest releases no longer ship an MSI." -ForegroundColor DarkYellow
                }
            }

            $removalConfirmed = $false
            # Prompt only when a user can actually answer. IsInputRedirected covers piped stdin; hosts
            # started with -NonInteractive refuse Read-Host, which the catch below converts to the same
            # forced path.
            $canPrompt = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
            if ($canPrompt) {
                try {
                    $confirmation = Read-Host -Prompt 'Remove the MSIX install of PowerShell Core? [y/N]' -ErrorAction Stop
                    $removalConfirmed = $confirmation -match '^\s*(y|yes)\s*$'
                }
                catch {
                    $canPrompt = $false
                }
            }
            if (-not $canPrompt) {
                Write-Host 'Non-interactive session: removing the MSIX install without confirmation.' -ForegroundColor DarkYellow
                $removalConfirmed = $true
            }
            if (-not $removalConfirmed) {
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

        # Dead app execution alias stubs left behind by a removed MSIX package are zero-byte files
        # reporting version 0.0.0.0; -All looks past them when a real pwsh sits further down the PATH.
        function Get-InstalledPwshCommand {
            Get-Command pwsh -All -ErrorAction SilentlyContinue |
                Where-Object { $_.Version -and $_.Version -ne [version]'0.0.0.0' } |
                    Select-Object -First 1
        }

        # Throws on failure. Returns $true when the install succeeded but a system restart is still
        # pending, $false on plain success.
        function Assert-WingetSucceeded {
            param([int]$ExitCode)

            # 0x8A150109 = install succeeded, restart required to finish; 0x8A15010B = restart initiated.
            if (@(0x8A150109, 0x8A15010B) -contains $ExitCode) {
                Write-Host 'PowerShell Core installed. A system restart is required to finish the installation.' -ForegroundColor DarkYellow
                return $true
            }
            # 0x8A150061 / 0x8A15010D = package already installed, 0x8A15002B = no applicable update.
            # All mean PowerShell Core is already present and current, which is a success here.
            if (@(0, 0x8A150061, 0x8A15002B, 0x8A15010D) -contains $ExitCode) {
                return $false
            }
            throw "WinGet failed to install PowerShell Core (exit code 0x$('{0:X}' -f $ExitCode))."
        }

        # Runs one winget MSI install attempt, framing winget's own output so it stays on screen without
        # folding into the return value (Out-Host), and returns winget's exit code. Every attempt uses the
        # same install arguments except for the pinned release: the first attempt passes no -Version and
        # takes the latest, each fallback retry pins one. The optional --version is splatted (an empty
        # array adds nothing) so the winget call and its output framing live in exactly one place.
        function Invoke-WingetMsiInstallAttempt {
            param([string]$Version)

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

            $versionArgument = if ($Version) { '--version', $Version } else { @() }

            Write-Host "`n---- WinGet output begins ----" -ForegroundColor Magenta
            Write-Host ''
            # --installer-type wix forces winget to the machine-wide WiX-built MSI installer.
            # Without it, winget has defaulted to the per-user MSIX package since PowerShell 7.6.0
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
                --custom $MSI_INSTALL_PARAMETERS `
                @versionArgument |
                Out-Host
            Write-Host "`n---- WinGet output ends ----" -ForegroundColor Magenta
            Write-Host ''
            return $LASTEXITCODE
        }

        # WinGet has defaulted to the per-user MSIX for PowerShell since 7.6.0, so the MSI is forced here.
        # When the newest release no longer ships an MSI (7.7.0 dropped it), earlier releases are tried
        # newest-first, never below 7.6.0. Routing is done purely on exit codes: winget's stdout is
        # localized and must not be parsed. Returns $true when a system restart is still pending.
        function Install-PowerShellMsiViaWinget {
            param([string[]]$AvailableVersions)

            # 0x8A150049 = no applicable installer: the release exists but ships no MSI for this request.
            $noApplicableInstaller = 0x8A150049

            Write-Host 'Installing PowerShell Core via WinGet' -ForegroundColor Yellow
            Write-Host "The download URL WinGet prints points to github.com/PowerShell/PowerShell, PowerShell's official release channel. WinGet verifies the installer hash before installing." -ForegroundColor Yellow
            $exitCode = Invoke-WingetMsiInstallAttempt
            if ($exitCode -ne $noApplicableInstaller) {
                return (Assert-WingetSucceeded -ExitCode $exitCode)
            }

            Write-Host 'The latest PowerShell Core release no longer ships an MSI package.' -ForegroundColor DarkYellow
            Write-Host 'Trying earlier releases, newest first, not going below 7.6.0...' -ForegroundColor Yellow
            # The first listed version is the latest, which the attempt above already covered.
            foreach ($version in ($AvailableVersions | Select-Object -Skip 1)) {
                if ([version]$version -lt [version]'7.6.0') {
                    break
                }
                Write-Host "Trying PowerShell Core $version..." -ForegroundColor Yellow
                $exitCode = Invoke-WingetMsiInstallAttempt -Version $version
                if ($exitCode -ne $noApplicableInstaller) {
                    return (Assert-WingetSucceeded -ExitCode $exitCode)
                }
            }
            throw 'No PowerShell Core release at or above 7.6.0 provides an MSI package via WinGet. PowerShell Core installation cannot continue.'
        }

        # Chocolatey is the fallback when WinGet is absent. Its powershell-core package fetches the MSI
        # from the same official release channel and verifies the checksum. Routing is on exit codes only.
        # Throws on failure. Returns $true when a system restart is still pending, $false on plain success.
        function Install-PowerShellMsiViaChocolatey {
            param([string]$ChocoExePath)

            Write-Host 'Installing PowerShell Core via Chocolatey' -ForegroundColor Yellow
            # Invoke the exact binary the presence check verified. Calling bare `choco` would resolve
            # through the session PATH, which may not yet contain Chocolatey's bin directory (typical when
            # Chocolatey was installed after this terminal opened). That fails with a non-terminating
            # CommandNotFoundException and leaves a stale $LASTEXITCODE from the last native command (often
            # 0), which would masquerade as success. Running $ChocoExePath directly makes that impossible:
            # either the verified binary runs and sets a fresh exit code, or the call fails loudly.
            # The package parameter stays quote-free so PS 5.1 and PS 7.3+ pass it identically (7.3+
            # escapes embedded quotes into the child's argv).
            Write-Host "The Chocolatey package downloads PowerShell's MSI from its official release channel (github.com/PowerShell/PowerShell) and verifies its checksum before installing." -ForegroundColor Yellow
            Write-Host "`n---- Chocolatey output begins ----" -ForegroundColor Magenta
            Write-Host ''
            # Out-Host keeps Chocolatey's output on screen without folding it into the return value.
            & $ChocoExePath install powershell-core -y --packageparameters '/CleanUpPath' | Out-Host
            $chocoExitCode = $LASTEXITCODE
            Write-Host "`n---- Chocolatey output ends ----" -ForegroundColor Magenta
            Write-Host ''
            # 1641 and 3010 mean the install succeeded and a reboot is pending.
            if (@(0, 1641, 3010) -notcontains $chocoExitCode) {
                throw "Chocolatey failed to install PowerShell Core (exit code $chocoExitCode)."
            }
            if (@(1641, 3010) -contains $chocoExitCode) {
                Write-Host 'PowerShell Core installed. A system restart is required to finish the installation.' -ForegroundColor DarkYellow
                return $true
            }
            return $false
        }

        # The MSI installs to C:\Program Files\PowerShell\7 and updates the machine PATH, which this
        # session cannot see. Add any missing persisted (Machine + User) entries so later steps in this
        # session can resolve pwsh. Entries are appended rather than replaced so session-local PATH
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

        # Both install routes place the MSI in Program Files\PowerShell\7, so that exact path is checked
        # first; the PATH search is only a fallback for nonstandard install locations. Resolving a path is
        # not proof the binary runs, so the resolved pwsh is executed to read its real version. Throws
        # when verification fails outright; a pending restart is reported without throwing.
        function Confirm-PowerShellCoreInstallation {
            param([bool]$RestartPending)

            Write-Host 'Verifying PowerShell Core installation...' -ForegroundColor Yellow
            $pwshPath = Join-Path $Env:ProgramFiles 'PowerShell\7\pwsh.exe'
            if (-not (Test-Path $pwshPath)) {
                $pwshCommand = Get-InstalledPwshCommand
                $pwshPath = if ($pwshCommand) { $pwshCommand.Source } else { $NULL }
            }

            $installedVersion = $NULL
            if ($pwshPath) {
                try {
                    $installedVersion = & $pwshPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
                    if ($LASTEXITCODE -ne 0) {
                        $installedVersion = $NULL
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
                Write-Host 'PowerShell Core installation failed.' -ForegroundColor Red
                throw 'PowerShell Core installation failed.'
            }
        }

        # ---- Preconditions ----------------------------------------------------

        # $IsWindows does not exist in Windows PowerShell 5.1 (which is Windows-only), so it is only
        # consulted on Core, where it always exists. This also keeps an inherited Set-StrictMode from
        # tripping over the undefined variable on 5.1.
        if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
            throw 'This script installs PowerShell Core on Windows only.'
        }
        Write-Host 'Installing PowerShell Core'

        Assert-Administrator
    }

    process {
        # ---- Install flow -----------------------------------------------------

        # Reported up front, before the package-manager check, purely as feedback. The installer still
        # runs below to apply any update, so an existing install does not gate the flow.
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

        # The package-manager check runs before the MSIX removal below, so removal can never leave the
        # machine without a way to install the replacement MSI.
        Write-Host 'Checking for WinGet presence...' -ForegroundColor Yellow
        $wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
        $chocoExePath = Join-Path $Env:ProgramData 'chocolatey\choco.exe'
        if ($wingetCommand) {
            Write-Host 'WinGet present' -ForegroundColor Green
        }
        else {
            Write-Host 'WinGet missing...' -ForegroundColor DarkYellow
            Write-Host 'Checking for Chocolatey presence...' -ForegroundColor Yellow
            # Deliberate pause, not dead latency: gives the user a window to abort (Ctrl+C) before the
            # flow continues towards a Chocolatey-based install.
            Start-Sleep 10
            if (Test-Path $chocoExePath) {
                Write-Host 'Chocolatey is present.' -ForegroundColor Green
            }
            else {
                # Red, not DarkMagenta: the legacy PowerShell console maps DarkMagenta to its blue
                # background, which would make this line invisible there.
                Write-Host 'Chocolatey is missing.' -ForegroundColor Red
                throw 'Neither Winget nor Chocolatey present. PowerShell Core installation cannot continue.'
            }
        }

        $availableVersions = @()
        if ($wingetCommand) {
            Write-Host 'Querying WinGet for the available PowerShell Core versions (any warnings below come from WinGet)...' -ForegroundColor Yellow
            $availableVersions = @(Get-AvailablePowerShellVersions)
        }

        # Detection uses -AllUsers, which needs the elevation asserted above.
        Remove-PowerShellMsixPackage -Pwsh_LatestAvailableVersion ($availableVersions | Select-Object -First 1)

        $restartPending = $false
        if ($wingetCommand) {
            $restartPending = Install-PowerShellMsiViaWinget -AvailableVersions $availableVersions
        }
        else {
            $restartPending = Install-PowerShellMsiViaChocolatey -ChocoExePath $chocoExePath
        }
    }

    end {
        # ---- Post-install: refresh session PATH, then verify ------------------
        Sync-SessionPathFromRegistry
        Confirm-PowerShellCoreInstallation -RestartPending $restartPending
    }
}

Install-PowerShellCore
