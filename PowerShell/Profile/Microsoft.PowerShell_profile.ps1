# Switching to TLS1.2 in this session (https://docs.microsoft.com/en-us/powershell/scripting/gallery/installing-psget?view=powershell-7.2)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

Import-Module -Name Terminal-Icons
Import-Module posh-git
Import-Module PSReadLine

# Enable support for the posh-git module for autocompletion
$env:POSH_GIT_ENABLED = $true

# Shows navigable menu of all options when hitting Tab
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

# Set Theme
oh-my-posh init pwsh --config "$HOME\Themes\PowerShell\Arch_Theme.omp.json" | Invoke-Expression

# oh-my-posh init pwsh --config "~/.poshthemes/Arch_Theme.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\Arch_Theme.omp.json" | Invoke-Expression
# oh-my-posh init pwsh --config 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/jandedobbeleer.omp.json' | Invoke-Expression

# Useful shortcuts for traversing directories
function cd...  { Set-Location ..\.. }
function cd.... { Set-Location ..\..\.. }

# Reload default Profile
function reload { . $PROFILE }

# Compute file hashes - useful for checking successful downloads 
function md5    { Get-FileHash -Algorithm MD5 $args }
function sha1   { Get-FileHash -Algorithm SHA1 $args }
function sha256 { Get-FileHash -Algorithm SHA256 $args }

