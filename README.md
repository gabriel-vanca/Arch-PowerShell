# Arch PowerShell

![Arch_Theme](PowerShell/Theme/Arch_Theme.png)

![Arch_Theme_battery](PowerShell/Theme/Arch_Theme_battery.png)

# Install Instructions

## 1. Install PowerShell Core

### Windows

Open a Powershell terminal with administrator priviledges and run the following:

```powershell
wget -O - https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Core/Windows_Install_Core.ps1 | powershell
```

Note: For Windows Server deployments, the script requires Chocolatey to be already installed.

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
