Write-Host "Installing Oh-My-Posh"

$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
if($osInfo.ProductType -eq 1) {
    Write-Host "Windows workstation (Windows 10/11) deployment detected. Installing via winget"
    winget install JanDeDobbeleer.OhMyPosh -s winget
} else {
    Write-Host "Windows server deployment detected. Installing via chocolatey"
    choco install oh-my-posh -y
}