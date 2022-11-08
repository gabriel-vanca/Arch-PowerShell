# Switching to TLS1.2 in this session (https://docs.microsoft.com/en-us/powershell/scripting/gallery/installing-psget?view=powershell-7.2)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

Import-Module posh-git
Import-Module PSReadLine
Import-Module -Name Terminal-Icons

# Shows navigable menu of all options when hitting Tab
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

# Set Theme
oh-my-posh init pwsh --config "$HOME\Themes\PowerShell\Arch_Theme.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "~/.poshthemes/Arch_Theme.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "C:\Themes\PowerShell Core\Arch_Theme.omp.json" | Invoke-Expression

# oh-my-posh init pwsh --config 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/jandedobbeleer.omp.json' | Invoke-Expression