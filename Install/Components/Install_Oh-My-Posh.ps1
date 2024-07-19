<#
.SYNOPSIS
    Installs Oh-my-posh
.DESCRIPTION
	Installs Oh-my-posh on Windows/Linux/MacOS via Winget/Chocolatey/Homebrew/script, as appropiate.
    Winget and Homebrew have priority, with Chocolatey having second-priority and script being last resort.
.EXAMPLE
	PS> ./Install_Oh-My-Posh
.LINK
	https://github.com/gabriel-vanca/Arch-PowerShell/Install/Components/Install_Oh-my-Posh.ps1
.NOTES
	Author: Gabriel Vanca
#>


#Requires -RunAsAdministrator

# Force use of TLS 1.2 for all downloads.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


Write-Host "Uninstall old version if installed"

pwsh -NoProfile -NonInteractive -Command {
    if (Get-Module oh-my-posh) {
        try {
            Uninstall-Module oh-my-posh -AllVersions -Force
        }
        catch {
            Write-Host "Deprecated Oh-My-Posh not present. Nothing to uninstall."
        }
    }
}

# ($NULL -eq $IsWindows) checks for Windows Sandbox enviroment
if ($IsWindows -or ($NULL -eq $IsWindows)) {
    powershell -NoProfile -NonInteractive -Command {
        if (Get-Module oh-my-posh) {
            try {
                Uninstall-Module oh-my-posh -AllVersions -Force
            }
            catch {
                Write-Host "Old Oh-My-Posh not present. Nothing to uninstall."
            }
        }
    }
}


Write-Host "Proceeding with installation"

# ($NULL -eq $IsWindows) checks for Windows Sandbox enviroment
if ($IsWindows -or ($NULL -eq $IsWindows)) {
    if (Get-AppPackage -name "Microsoft.DesktopAppInstaller") {
        Write-Host "WinGet present" -ForegroundColor DarkGreen
    }
    else {
        Write-Host "WinGet missing..."  -ForegroundColor DarkYellow
        Write-Host "Checking for Chocolatey presence..."  -ForegroundColor DarkYellow
        Start-Sleep 10

        # Expected path of the choco.exe file.
        $chocoInstallPath = "$Env:ProgramData/chocolatey/choco.exe"
        if (Test-Path "$chocoInstallPath") {
            Write-Host "Chocolatey is present."  -ForegroundColor DarkGreen
            Write-Host "Installing oh-my-posh via Chocolatey" -ForegroundColor DarkYellow
            choco install oh-my-posh -y
        }
        else {
            Write-Host "Chocolatey is missing."  -ForegroundColor DarkMagenta
            Write-Host "Installing oh-my-posh manually via script" -ForegroundColor DarkYellow
            Start-Sleep -Seconds 5
            Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))
        }
    }
}
else {
    if ($IsLinux) {
        Write-Host "Linux deployment detected."
        Write-Host "Installing via Homebrew" -ForegroundColor DarkYellow
        try {
            brew install jandedobbeleer/oh-my-posh/oh-my-posh
            brew update && brew upgrade oh-my-posh
        }
        catch {
            Write-Error "Installing via Homebrew failed"
            Write-Host "Installing manually" -ForegroundColor DarkYellow
            curl -s https://ohmyposh.dev/install.sh | bash -s
        }
    }
    else {
        if ($IsMacOS) {
            Write-Host "MacOS deployment detected."
            Write-Host "Installing via Homebrew" -ForegroundColor DarkYellow
            try {
                brew install jandedobbeleer/oh-my-posh/oh-my-posh
                brew update && brew upgrade oh-my-posh
            }
            catch {
                Write-Error "Installing via Homebrew failed"
                Write-Host "Installing manually" -ForegroundColor DarkYellow
                curl -s https://ohmyposh.dev/install.sh | bash -s
            }
        }
        else {
            Write-Error "Unknown deployment"
            Write-Host "Installing manually" -ForegroundColor DarkYellow
            curl -s https://ohmyposh.dev/install.sh | bash -s
        }
    }
}

Write-Host "Refreshing terminal"
.$PROFILE
# ($NULL -eq $IsWindows) checks for Windows Sandbox enviroment
if ($IsWindows -or ($NULL -eq $IsWindows)) {
    # Expected path of the choco.exe file.
    $chocoInstallPath = "$Env:ProgramData/chocolatey/choco.exe"
    if (Test-Path -path $chocoInstallPath) {
        # Make `refreshenv` available right away, by defining the $env:ChocolateyInstall
        # variable and importing the Chocolatey profile module.
        $env:ChocolateyInstall = Convert-Path "$((Get-Command choco).Path)\..\.."   
        Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
        Update-SessionEnvironment
        refreshenv
    }
}

Write-Host "Testing installation" -ForegroundColor DarkYellow
try {
    oh-my-posh version
    Write-Host "Oh-my-posh installation succesful." -ForegroundColor DarkGreen
}
catch {
    Write-Error "Oh-my-posh installallation failed"
    throw "Oh-my-posh installallation failure"
}
