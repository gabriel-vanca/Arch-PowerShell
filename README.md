# Arch PowerShell

![Arch_Theme](PowerShell/Theme/Arch_Theme.png)

![Arch_Theme_battery](PowerShell/Theme/Arch_Theme_battery.png)

# Install Instructions

## 1. Install PowerShell Core

### Windows

Open a classic PowerShell terminal with administrator priviledges and run the following:

```powershell
wget -O - https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Core/Windows_Install_Core.ps1 | powershell
```

Note: For Windows Server deployments, the script requires Chocolatey to be already installed. Non-server deplyments will use winget (also known as App Installer) which comes bundled with Windows 11 and the latest versions of Windows 10 by default.

### Ubuntu

Open a terminal and run the following with administrator priviledges:

```bash
sudo wget -O - https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Core/Ubuntu_Install_Core.sh | bash
```

### MacOS

Open a terminal and run the following with administrator priviledges:

```bash
sudo wget -O - https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Core/MacOS_Install_Core.sh | bash
```

Note: The script requires Homebrew to be already installed.

## 2. Configure PowerShell

Open a PowerShell terminal and run the following commands.

Note: On Windows you need to run this from a terminal with admin priviledges. On Linux, make sure the command is not run from the root user as in that case the theme will only be available for the root user.

```powershell
Invoke-RestMethod https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Configure/Configure.ps1 | pwsh
```
