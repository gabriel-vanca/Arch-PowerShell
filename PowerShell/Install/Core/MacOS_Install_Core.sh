# Source: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-macos?view=powershell-7.3

# Install PowerShell
brew install --cask powershell
# Make PowerShell the default shell
sudo chsh --shell /usr/bin/pwsh
# Check default shell
echo $SHELL
echo $env:SHELL
# Switch to PowerShell
pwsh