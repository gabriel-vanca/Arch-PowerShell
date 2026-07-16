#!/bin/bash
# Source: https://learn.microsoft.com/en-gb/powershell/scripting/install/install-ubuntu
#
# Install methodology:
# * Run WITHOUT sudo (wget | bash). The default-shell change must target the invoking
#   user, never root, so the script refuses to run as root and calls sudo itself for
#   the steps that need it, prompting for the password.
# * PowerShell installs machine-wide from Microsoft's apt repository:
#   /opt/microsoft/powershell/7, symlinked at /usr/bin/pwsh for all users.
#
# Default-shell policy and security notes:
# * The root shell is never changed. If pwsh is ever broken, badly updated or
#   uninstalled, root must still be able to log in, and recovery expects a
#   Bourne-compatible shell. System/service accounts likewise keep their shells.
# * The invoking user's login shell is changed via plain chsh (no sudo), so the
#   change can never silently retarget root or another account.
# * Future users get pwsh by default via DSHELL in /etc/adduser.conf (the Debian
#   adduser tool) and via useradd -D (the low-level useradd default).
# * apt-installed pwsh is root-owned under /opt and /usr/bin, so there is no
#   user-writable-binary escalation concern (unlike Homebrew on macOS).
# * Remote-tooling caveat: ssh remote commands, scp and rsync run through the login
#   shell and assume POSIX quoting; quoting-heavy invocations may break under pwsh.

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Do not run this script as root or with sudo. The default-shell change must" >&2
    echo "apply to your user, not root. The script prompts for sudo when needed." >&2
    exit 1
fi

# Update the list of packages
sudo apt-get update
# Install pre-requisite packages
sudo apt-get install -y wget apt-transport-https software-properties-common
# Download and register the Microsoft repository GPG keys
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
sudo dpkg -i /tmp/packages-microsoft-prod.deb
rm -f /tmp/packages-microsoft-prod.deb
# Update the list of packages after adding packages.microsoft.com
sudo apt-get update
# Install PowerShell
sudo apt-get install -y powershell

PWSH_PATH="$(command -v pwsh || true)"
if [ -z "$PWSH_PATH" ]; then
    PWSH_PATH="/usr/bin/pwsh"
fi
if [ ! -x "$PWSH_PATH" ]; then
    echo "pwsh was not found after installation. PowerShell Core installation failed." >&2
    exit 1
fi

# chsh rejects any shell not listed in /etc/shells, so register pwsh there first.
if ! grep -qx "$PWSH_PATH" /etc/shells; then
    echo "Registering $PWSH_PATH as a valid login shell (sudo will prompt for your password)..."
    echo "$PWSH_PATH" | sudo tee -a /etc/shells >/dev/null
fi

echo "Setting pwsh as the default login shell for $USER (chsh will prompt for your password)..."
chsh -s "$PWSH_PATH"

# Make pwsh the default shell for future user accounts. Root and existing accounts
# are deliberately left untouched.
echo "Setting pwsh as the default shell for future user accounts..."
if [ -f /etc/adduser.conf ]; then
    if grep -q '^DSHELL=' /etc/adduser.conf; then
        sudo sed -i "s|^DSHELL=.*|DSHELL=$PWSH_PATH|" /etc/adduser.conf
    else
        echo "DSHELL=$PWSH_PATH" | sudo tee -a /etc/adduser.conf >/dev/null
    fi
fi
sudo useradd -D -s "$PWSH_PATH"

# Ghostty: set pwsh as the default shell if Ghostty is present.
GHOSTTY_CONFIG="$HOME/.config/ghostty/config"
if command -v ghostty >/dev/null 2>&1 || [ -e "$GHOSTTY_CONFIG" ]; then
    if [ -e "$GHOSTTY_CONFIG" ] && grep -Eq '^[[:space:]]*command[[:space:]]*=' "$GHOSTTY_CONFIG"; then
        echo "Ghostty already defines 'command' in $GHOSTTY_CONFIG; leaving it untouched."
    else
        mkdir -p "$(dirname "$GHOSTTY_CONFIG")"
        printf 'command = %s\n' "$PWSH_PATH" >>"$GHOSTTY_CONFIG"
        echo "Ghostty: pwsh set as the default shell in $GHOSTTY_CONFIG."
    fi
fi

# Alacritty: set pwsh as the default shell if Alacritty is present.
ALACRITTY_CONFIG="$HOME/.config/alacritty/alacritty.toml"
if command -v alacritty >/dev/null 2>&1 || [ -e "$ALACRITTY_CONFIG" ]; then
    if [ -e "$ALACRITTY_CONFIG" ] && grep -Eq '^\[(terminal\.)?shell\]|^[[:space:]]*shell[[:space:]]*=' "$ALACRITTY_CONFIG"; then
        echo "Alacritty already defines a shell in $ALACRITTY_CONFIG; leaving it untouched."
    else
        mkdir -p "$(dirname "$ALACRITTY_CONFIG")"
        printf '\n[terminal.shell]\nprogram = "%s"\n' "$PWSH_PATH" >>"$ALACRITTY_CONFIG"
        echo "Alacritty: pwsh set as the default shell in $ALACRITTY_CONFIG."
    fi
fi

echo "Verifying the PowerShell Core installation..."
"$PWSH_PATH" -NoProfile -Command 'Write-Host "Installed PowerShell Core version: $($PSVersionTable.PSVersion)" -ForegroundColor DarkGreen'
echo "PowerShell Core installation successful. The default-shell change takes effect at next login."
