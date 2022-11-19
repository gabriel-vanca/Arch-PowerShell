#Requires -RunAsAdministrator

# Set Repository as trusted
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted


Write-Host "Installing Powershell Core modules"
Install-Module posh-git -Scope AllUsers -Force
Install-Module -Name PSReadLine -Scope AllUsers -Force
Install-Module -Name Terminal-Icons -Repository PSGallery -Scope AllUsers -Force
Write-Host "PowerShell Core modules installed:"
Get-Module –ListAvailable
