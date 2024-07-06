# Arch PowerShell

![Arch_Theme](Theme/Arch_Theme.png)

# Install Instructions

## 1. Install PowerShell Core

### Windows

Open a classic PowerShell terminal with administrator priviledges and run the following:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
wget -O - https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Core/Windows_Install_Core.ps1 | powershell
```

Notes:

* For Windows Server deployments, the script requires Chocolatey to be already installed. Non-server deplyments will use winget (also known as App Installer) which comes bundled with Windows 11 and the latest versions of Windows 10 by default.
* For workstations, Windows 10 1809+ or Windows 11 is required. For Servers, Windows Server 2012 R2 or later is required.

### Ubuntu

Open a terminal and run the following with root priviledges:

```bash
sudo wget -O - https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Core/Ubuntu_Install_Core.sh | bash
```

Note: Version 18.04 or above is required.

### MacOS

Open a terminal and run the following with administrator priviledges:

```bash
sudo wget -O - https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Core/MacOS_Install_Core.sh | bash
```

Note:

* The script requires Homebrew to be already installed.
* MacOS Big Sur 11.5 or later is required.

## 2. Install Additional PowerShell Components

Open an elevated PowerShell terminal and run the following commands in order to install the necessary PowerShell modules, Oh-my-Posh and the necessary fonts.

```powershell
Invoke-RestMethod https://raw.githubusercontent.com/gabriel-vanca/Arch-PowerShell/main/PowerShell/Install/Additional_Components/Install_Additional_Components.ps1 | Invoke-Expression
```

## 3. Configure PowerShell Profile

Open a PowerShell terminal and run the following commands.

Notes:

* On Windows you need to run this from a terminal with admin priviledges.
* On Linux, make sure the command is **not** run from the root user as in that case the theme will only be available for the root user.

```powershell

# Install Necessary Fonts
oh-my-posh font install FiraCode


# Install Oh-my-Posh Theme

```

# Included Tech Fonts (Coding and Terminal Fonts)

The following fonts will be installed automatically

## MonaLisa

![1692311024923](image/README/1692311024923.png)

[MonoLisa](https://www.monolisa.dev/)

## JetBrains NF

![1692311061880](image/README/1692311061880.png)

![1692311067308](image/README/1692311067308.png)

## Adobe Source Code Pro

![1692311110881](image/README/1692311110881.png)

![1692311120520](image/README/1692311120520.png)

[Source Code from Adobe Originals](https://fonts.adobe.com/fonts/source-code-pro)

[https://github.com/adobe-fonts/source-code-pro/releases](https://github.com/adobe-fonts/source-code-pro/releases)

## Cousine

![1692311140214](image/README/1692311140214.png)

[Cousine - Google Fonts](https://fonts.google.com/specimen/Cousine)

## Roboto

![1692311165810](image/README/1692311165810.png)

## Hasklug NF

![1692311187964](image/README/1692311187964.png)

## FiraCode NF

![1692311213831](image/README/1692311213831.png)

![1692311216348](image/README/1692311216348.png)

## Cascadia Code NF

![1692311243540](image/README/1692311243540.png)

![1692311247114](image/README/1692311247114.png)

## Monoid

![1692311272841](image/README/1692311272841.png)

## Go Mono NF
