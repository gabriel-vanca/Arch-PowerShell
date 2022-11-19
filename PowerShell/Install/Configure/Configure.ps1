#Requires -RunAsAdministrator

#Install PowerShell Modules
wget -O - https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Configure/Install_PS_Modules.ps1 | pwsh

# Install Oh-my-Posh
wget -O - https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Configure/Install_Oh-my-Posh.ps1 | pwsh

# Install Necessary Fonts
oh-my-posh font install

# Install Oh-my-Posh Theme
