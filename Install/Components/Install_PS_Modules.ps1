#Requires -RunAsAdministrator

# Set Repository as trusted
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted

Write-Host "Uninstall old versions if present"
try {
    Uninstall-Module Terminal-Icons -AllVersions
    Uninstall-Module posh-git -AllVersions
    Uninstall-Module PSReadLine -AllVersions
} catch {
    <#Uninstall will throw error if not modules installed. No need to handle this exception beyond that.#>
}

Write-Host "Installing modules:"
Install-Module -Name posh-git -Scope AllUsers -Force
Install-Module -Name PSReadLine -Scope AllUsers -Force
Install-Module -Name Terminal-Icons -Repository PSGallery -Scope AllUsers -Force

Import-Module -Name Terminal-Icons
Import-Module -Name posh-git
Import-Module -Name PSReadLine

Write-Host "Module installation completed." -ForegroundColor DarkGreen
