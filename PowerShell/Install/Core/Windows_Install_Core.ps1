#Requires -RunAsAdministrator

Write-Host "Installing PowerShell Core"

$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
if($osInfo.ProductType -eq 1) {
    Write-Host "Windows workstation (Windows 10/11) deployment detected. Installing via winget"
    winget search Microsoft.PowerShell
    winget install --id Microsoft.Powershell --source winget
} else {
    Write-Host "Windows server deployment detected. Installing via chocolatey"
    choco install oh-my-posh -y
}

Write-Host "Switching to PowerShell Core"
pwsh