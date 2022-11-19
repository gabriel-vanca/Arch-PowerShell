#Requires -RunAsAdministrator

Write-Host "Installing Oh-My-Posh"

if($IsWindows) {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if($osInfo.ProductType -eq 1) {
        Write-Host "Windows workstation (Windows 10/11) deployment detected. Installing via winget"
        winget install JanDeDobbeleer.OhMyPosh -s winget
    } else {
        Write-Host "Windows Server deployment detected. Installing via Chocolatey"
        choco install oh-my-posh -y
    }
} else {
    if($IsLinux) {
        Write-Host "Linux deployment detected. Installing via Github"
        wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
        sudo chmod +x /usr/local/bin/oh-my-posh
    } else {
        if($IsMacOS) {
            Write-Host "MacOS deployment detected. Installing via Homebrew"
            brew install jandedobbeleer/oh-my-posh/oh-my-posh
        }
    }
}