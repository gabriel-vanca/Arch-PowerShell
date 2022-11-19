#Requires -RunAsAdministrator

#Install PowerShell Modules
if($IsWindows) {
    Invoke-RestMethod https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Configure/Install_PS_Modules.ps1 | pwsh -noprofile
} else {
    Invoke-RestMethod https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Configure/Install_PS_Modules.ps1 | sudo pwsh -noprofile
}
# Install Oh-my-Posh
if($IsWindows) {
    Invoke-RestMethod https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Configure/Install_Oh-my-Posh.ps1 | pwsh
} else {
    Invoke-RestMethod https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Configure/Install_Oh-my-Posh.ps1 | sudo pwsh
}
# Install Necessary Fonts
oh-my-posh font install

# Install Oh-my-Posh Theme




# wget -O - https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Configure/Install_PS_Modules.ps1 | pwsh