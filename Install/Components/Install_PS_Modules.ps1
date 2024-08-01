#Requires -RunAsAdministrator

# Set Repository as trusted
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted

Write-Host "Uninstall old versions if present"
try {
    Uninstall-Module -Name Terminal-Icons -AllVersions
    Uninstall-Module -Name posh-git -AllVersions
    Uninstall-Module -Name PSReadLine -AllVersions
    Uninstall-Module -Name Profiler -AllVersions
    Uninstall-Module -Name CompletionPredictor -AllVersions
    Uninstall-Module -Name Microsoft.PowerShell.UnixTabCompletion -AllVersions
    Uninstall-Module -Name Microsoft.PowerShell.ConsoleGuiTools -AllVersions
}
catch {
    <#Uninstall will throw error if not modules installed. No need to handle this exception beyond that.#>
}

Write-Host "Installing modules:"
Install-Module -Name posh-git -Scope AllUsers -Force
Install-Module -Name PSReadLine -Scope AllUsers -Force
Install-Module -Name Terminal-Icons -Repository PSGallery -Scope AllUsers -Force
Install-Module -Name Profiler -Repository PSGallery -Scope AllUsers -Force
Install-Module -Name CompletionPredictor -Repository PSGallery -Scope AllUsers -Force
Install-Module -Name Microsoft.PowerShell.ConsoleGuiTools -Repository PSGallery -Scope AllUsers -Force
    
if ($IsWindows -or ($NULL -eq $IsWindows)) {
    #  Disable PSReadline Warning
    # https://stackoverflow.com/questions/66748513/re-enable-import-module-psreadline-warning
    Set-ItemProperty 'registry::HKEY_CURRENT_USER\Control Panel\Accessibility\Blind Access' On 0
}
else {
    Install-Module Microsoft.PowerShell.UnixTabCompletion -Repository PSGallery -Scope AllUsers -AcceptLicense -Force
}    

Write-Host "Module installation completed." -ForegroundColor DarkGreen
