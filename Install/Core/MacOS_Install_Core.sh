#!/bin/bash
# Source: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-macos
#
# Install methodology:
# * Run WITHOUT sudo (curl | bash). Homebrew refuses to run as root, and the
#   default-shell change must target the invoking user, never root. The script calls
#   sudo itself for the one step that needs it (registering pwsh in /etc/shells), and
#   the Homebrew cask prompts for the password when Microsoft's .pkg installer runs.
# * The Homebrew cask runs Microsoft's .pkg installer, so the install is machine-wide:
#   /usr/local/microsoft/powershell/7, with a pwsh symlink available to all users.
#
# Default-shell policy and security notes:
# * The root shell is never changed. If pwsh is ever broken, badly updated or
#   uninstalled, root must still be able to log in, and recovery/single-user mode
#   expects a Bourne-compatible shell.
# * Only the invoking user's login shell is changed, via plain chsh (no sudo), so the
#   change can never silently retarget root or another account.
# * macOS has no supported setting for the default shell of future user accounts (new
#   accounts always get /bin/zsh), so each new user has to opt in themselves.
# * Homebrew's directories are writable by the installing user without sudo, so a
#   brew-managed pwsh must never become the login shell of root or any other
#   privileged account: that would be a privilege-escalation vector. Per-user only.
# * Remote-tooling caveat: ssh remote commands, scp and rsync run through the login
#   shell and assume POSIX quoting; quoting-heavy invocations may break under pwsh.

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Do not run this script as root or with sudo. Homebrew refuses to run as root," >&2
    echo "and the default-shell change must apply to your user, not root." >&2
    exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required but was not found. Install it from https://brew.sh first." >&2
    exit 1
fi

echo "Installing PowerShell Core (machine-wide, via the Homebrew cask)..."
brew install --cask powershell

# The .pkg links pwsh at /usr/local/bin/pwsh; fall back to that if PATH misses it.
PWSH_PATH="$(command -v pwsh || true)"
if [ -z "$PWSH_PATH" ]; then
    PWSH_PATH="/usr/local/bin/pwsh"
fi
if [ ! -x "$PWSH_PATH" ]; then
    echo "pwsh was not found after installation. PowerShell Core installation failed." >&2
    exit 1
fi

# chsh rejects any shell not listed in /etc/shells, so register pwsh there first.
# This is the only step that needs sudo; it prompts for the password here.
if ! grep -qx "$PWSH_PATH" /etc/shells; then
    echo "Registering $PWSH_PATH as a valid login shell (sudo will prompt for your password)..."
    echo "$PWSH_PATH" | sudo tee -a /etc/shells >/dev/null
fi

echo "Setting pwsh as the default login shell for $USER (chsh will prompt for your password)..."
chsh -s "$PWSH_PATH"

# Ghostty: set pwsh as the default shell if Ghostty is present. On macOS Ghostty
# prefers ~/Library/Application Support/com.mitchellh.ghostty/config but also reads
# the XDG path; write to whichever already exists, defaulting to the XDG path.
GHOSTTY_CONFIG="$HOME/.config/ghostty/config"
GHOSTTY_APPSUPPORT_CONFIG="$HOME/Library/Application Support/com.mitchellh.ghostty/config"
if [ -e "$GHOSTTY_APPSUPPORT_CONFIG" ]; then
    GHOSTTY_CONFIG="$GHOSTTY_APPSUPPORT_CONFIG"
fi
if [ -d "/Applications/Ghostty.app" ] || command -v ghostty >/dev/null 2>&1 || [ -e "$GHOSTTY_CONFIG" ]; then
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
if [ -d "/Applications/Alacritty.app" ] || command -v alacritty >/dev/null 2>&1 || [ -e "$ALACRITTY_CONFIG" ]; then
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
