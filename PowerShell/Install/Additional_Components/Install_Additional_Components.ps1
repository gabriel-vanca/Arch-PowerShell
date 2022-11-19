#Requires -RunAsAdministrator

#Install PowerShell Modules
if($IsWindows) {
    Invoke-RestMethod https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Additional_Components/Install_PS_Modules.ps1 | Invoke-Expression
} else {
    sudo pwsh -noprofile -command {Invoke-RestMethod https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Additional_Components/Install_PS_Modules.ps1 | Invoke-Expression}
}

# Install Oh-my-Posh
$oh_my_posh_install = Invoke-RestMethod https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Additional_Components/Install_Oh-my-Posh.ps1
Invoke-Expression $oh_my_posh_install

# Install Necessary Fonts
oh-my-posh font install FiraCode


# Install Oh-my-Posh Theme




# wget -O - https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Additional_Components/Install_PS_Modules.ps1 | pwsh