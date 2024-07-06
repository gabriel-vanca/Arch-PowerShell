#Requires -RunAsAdministrator

# ($NULL -eq $IsWindows) checks for Windows Sandbox enviroment
if($IsWindows -or ($NULL -eq $IsWindows)) {
    Write-Host "Installing PowerShell Core"
} else {
    throw "Not Windows"
}

$wingetBasedInstall = $False
$chocoBasedInstall = $False
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
if($osInfo.ProductType -eq 1) {
    Write-Host "Windows workstation (Windows 10/11) deployment detected."
    $wingetBasedInstall = $True
} else {
    Write-Host "Windows Server deployment detected."

    if (Get-AppPackage -name "Microsoft.DesktopAppInstaller") {
        Write-Host "WinGet present" -ForegroundColor DarkGreen
        $wingetBasedInstall = $True
    } else {
        Write-Host "WinGet missing"  -ForegroundColor DarkYellow
        $wingetBasedInstall = $False
        # Expected path of the choco.exe file.
        $chocoInstallPath = "$Env:ProgramData/chocolatey/choco.exe"
        if (Test-Path "$chocoInstallPath") {
            Write-Host "Chocolatey is present."  -ForegroundColor DarkGreen
            $chocoBasedInstall = $True
        } else {
            Write-Host "Chocolatey is missing."  -ForegroundColor DarkMagenta
            $chocoBasedInstall = $False
        }
    }
}

if($wingetBasedInstall) {
    Write-Host "Installing PowerShell Core via WinGet" -ForegroundColor DarkYellow 
    winget install -e --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements -s
} else {
    if($chocoBasedInstall) {
        Write-Host "Installing PowerShell Core via Chocolatey" -ForegroundColor DarkYellow
        choco install powershell-core -y --packageparameters '"/CleanUpPath"'
    } else {
        throw "Neither Winget nor Chocolatey present"
    }
}

Write-Host "List current Powershell Core version" -ForegroundColor DarkGreen
pwsh {$PSVersionTable}
pwsh
