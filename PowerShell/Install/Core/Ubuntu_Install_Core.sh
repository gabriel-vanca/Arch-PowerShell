# Source: https://learn.microsoft.com/en-gb/powershell/scripting/install/install-ubuntu?view=powershell-7.2


# Update the list of packages
sudo apt-get update
# Install pre-requisite packages.
sudo apt-get install -y wget apt-transport-https software-properties-common
# Download the Microsoft repository GPG keys
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
# Register the Microsoft repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb
# Update the list of packages after we added packages.microsoft.com
sudo apt-get update
# Install PowerShell
sudo apt-get install -y powershell
# Make PowerShell the default shell
sudo chsh --shell /usr/bin/pwsh
# Check default shell
echo $SHELL
echo $env:SHELL
# Switch to PowerShell
pwsh