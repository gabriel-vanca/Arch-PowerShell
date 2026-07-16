<#
.SYNOPSIS

.DESCRIPTION

.EXAMPLE
	PS> ./ArchPowerShell
.LINK
	https://github.com/gabriel-vanca/https://github.com/gabriel-vanca/Arch-PowerShell
.NOTES
	Author: Gabriel Vanca
#>

#Requires -PSEdition Core

# Force use of TLS 1.3 for all downloads.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls13

# TODO [String]$VersionToLookFor = "14.0.30704.0"
# TODO [Switch]$ChocolateyInstalled = $False
# TODO [Switch]$MustUseChocolatey = $False

Write-Host "List current Powershell Core version" -ForegroundColor DarkGreen
$PSVersionTable

Write-Host "On Windows you need to run this script from a terminal with admin privileges. `nOn Linux, make sure the command is **not** run from the root user as in that case the theme will only be available for the root user." -ForegroundColor DarkYellow

#Check Administrator privileges manually
# ($NULL -eq $IsWindows) checks for Windows Sandbox enviroment
if ($IsWindows -or ($NULL -eq $IsWindows)) {
	$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
	if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -eq $true) {
		Write-Host "This session is running with Administrator privileges." -ForegroundColor DarkGreen
	}
 else {
		Write-Host "This session is not running with Administrator privileges." -ForegroundColor DarkRed
		$Host.UI.RawUI.WindowTitle = "[Not Admin]: " + $host.UI.RawUI.WindowTitle
		Write-Host "Please close this prompt and restart as admin" -ForegroundColor DarkRed
		Start-Sleep -Seconds 10
		throw "This session is not running with Administrator privileges."
	}
}

Write-Host "Step 1: Install/Update PowerShell Modules"
if ($IsWindows -or ($NULL -eq $IsWindows)) {
	Write-Host "PowerShell Core Modules:"
	Invoke-RestMethod "https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/Install/Components/Install_PS_Modules.ps1" | Invoke-Expression
	Write-Host "PowerShell Core modules installed:"
	Get-InstalledModule

	Write-Host "PowerShell Desktop Modules:"
	powershell -NoProfile -NonInteractive -Command {
		Invoke-RestMethod "https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/Install/Components/Install_PS_Modules.ps1" | Invoke-Expression
	}
	Write-Host "PowerShell Desktop modules installed:"
	Get-InstalledModule
}
else {
	sudo pwsh -noprofile -command {
		Invoke-RestMethod "https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/Install/Components/Install_PS_Modules.ps1" | Invoke-Expression

		Write-Host "PowerShell Core modules installed:"
		Get-InstalledModule
	}
}

Write-Host "Step 2: Install/Update Oh-my-Posh"
Invoke-RestMethod "https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/Install/Components/Install_Oh-My-Posh.ps1" | Invoke-Expression


Write-Host "Step 3: Deploy Powershell Fonts"
Invoke-RestMethod "https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/Install/Components/Install_Fonts.ps1" | Invoke-Expression

# TODO This takes a lot of space. Make sure it only works for Workstation Windows PCs.
Update-Help -Force -ErrorAction SilentlyContinue
