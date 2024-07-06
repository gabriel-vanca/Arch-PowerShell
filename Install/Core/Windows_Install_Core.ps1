#Requires -RunAsAdministrator

# ($NULL -eq $IsWindows) checks for Windows Sandbox enviroment
if($IsWindows -or ($NULL -eq $IsWindows)) {
    Write-Host "Installing PowerShell Core"
} else {
    throw "Not Windows"
}

if (Get-AppPackage -name "Microsoft.DesktopAppInstaller") {
    Write-Host "WinGet present" -ForegroundColor DarkGreen
    Write-Host "Installing PowerShell Core via WinGet" -ForegroundColor DarkYellow 
    winget install -e --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements -s
} else {
    Write-Host "WinGet missing..."  -ForegroundColor DarkYellow
    Write-Host "Checking for Chocolatey presence..."  -ForegroundColor DarkYellow
    Start-Sleep 10
    # Expected path of the choco.exe file.
    $chocoInstallPath = "$Env:ProgramData/chocolatey/choco.exe"
    if (Test-Path "$chocoInstallPath") {
        Write-Host "Chocolatey is present."  -ForegroundColor DarkGreen
        Write-Host "Installing PowerShell Core via Chocolatey" -ForegroundColor DarkYellow
        choco install powershell-core -y --packageparameters '"/CleanUpPath"'
    } else {
        Write-Host "Chocolatey is missing."  -ForegroundColor DarkMagenta
        throw "Neither Winget nor Chocolatey present"
    }
}

Write-Host "List current Powershell Core version" -ForegroundColor DarkGreen
pwsh {$PSVersionTable}
pwsh
