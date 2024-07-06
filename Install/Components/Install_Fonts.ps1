# WARNING: This does not work without admin access. 
    # The files must be installed manually from File explorer or Powershell if admin access is lacking.
    # Even so it might not work properly. Fonts should always be installed as admin.

#Requires -RunAsAdministrator

# Force use of TLS 1.2 for all downloads.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


Write-Host "Step 1: Installing Oh-My-Posh" # (https://ohmyposh.dev/docs/)


# Font source: https://github.com/ryanoasis/nerd-fonts
Write-Host "Step 2: Installing Fonts via Oh-my-posh"

oh-my-posh font install CascadiaCode
oh-my-posh font install Cousine
oh-my-posh font install FiraCode
oh-my-posh font install Go-Mono
oh-my-posh font install Hack
oh-my-posh font install Hasklig
oh-my-posh font install JetBrainsMono
oh-my-posh font install LiberationMono
oh-my-posh font install Meslo
oh-my-posh font install Monoid
oh-my-posh font install NerdFontsSymbolsOnly
oh-my-posh font install ProFont
oh-my-posh font install RobotoMono
oh-my-posh font install SourceCodePro


Write-Host "Step 3: Additional tech fonts installation"

Write-Host "Downloading \Fonts and preparing them for installation"

$repoDownloadLocalPath  = "$env:Temp\Fonts_to_install"
#Ensure folder is empty
if(Test-Path -path $repoDownloadLocalPath)
{ 
    Remove-Item $repoDownloadLocalPath -Recurse -Force
}

$repoUrl = "https://github.com/gabriel-vanca/ArchPowerShell"  
git clone $repoUrl $repoDownloadLocalPath --depth 1 --progress -v
Get-ChildItem $repoDownloadLocalPath -Recurse | Unblock-File

$gitRepoPath = $repoDownloadLocalPath + "\.git"
Remove-Item $gitRepoPath -Recurse -Force

$fontsDownloadPath = $repoDownloadLocalPath + "\Fonts"

Write-Host "Installing content of the \Fonts directory"
$scriptPath = "https://raw.githubusercontent.com/gabriel-vanca/PowerShell_Library/main/Scripts/Core/Fonts/Install-Fonts.ps1"
$WebClient = New-Object Net.WebClient
$deploymentScript = $WebClient.DownloadString($scriptPath)
$deploymentScript = [Scriptblock]::Create($deploymentScript)
Invoke-Command -ScriptBlock $deploymentScript -ArgumentList ($fontsDownloadPath) -NoNewScope

Remove-Item $repoDownloadLocalPath -Recurse -Force


Write-Host "Step 4: Refreshing terminal"
.$PROFILE
# ($NULL -eq $IsWindows) checks for Windows Sandbox enviroment
if($IsWindows -or ($NULL -eq $IsWindows)) {
    # Expected path of the choco.exe file.
    $chocoInstallPath = "$Env:ProgramData/chocolatey/choco.exe"
    if(Test-Path -path $chocoInstallPath) {
        # Make `refreshenv` available right away, by defining the $env:ChocolateyInstall
        # variable and importing the Chocolatey profile module.
        $env:ChocolateyInstall = Convert-Path "$((Get-Command choco).Path)\..\.."   
        Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
        Update-SessionEnvironment
        refreshenv
    }
}
