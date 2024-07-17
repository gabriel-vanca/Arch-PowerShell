# Switching to TLS1.2 in this session (https://docs.microsoft.com/en-us/powershell/scripting/gallery/installing-psget?view=powershell-7.2)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

Import-Module -Name Terminal-Icons
Import-Module -Name posh-git
Import-Module -Name PSReadLine
Import-Module -Name CompletionPredictor

# Enable support for the posh-git module for autocompletion
$env:POSH_GIT_ENABLED = $true

# Activates CompletionPredictor
# The CompletionPredictor module adds an IntelliSense experience for
# anything that can be tab-completed in PowerShell.
# With PSReadLine set to InlineView, you get the normal tab completion experience.
# When you switch to ListView, you get the IntelliSense experience.
Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ShowToolTips

# Shows navigable menu of history options when hitting Tab. F2 by default
Set-PSReadlineKeyHandler -Chord Tab -Function SwitchPredictionView
# Shows full menu of all possible options when hitting Shift+Tab. Not navigable.
Set-PSReadLineKeyHandler -Chord Shift+Tab -Function MenuComplete
# Search command history for command lines that start with the current contents of the command line
Set-PSReadLineKeyHandler -Chord PageUp -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Chord PageDown -Function HistorySearchForward

if($IsWindows -eq $False) {
    # PowerShell parameter completers for native commands on Linux and macOS.
    # This module uses completers supplied in traditional Unix shells to complete native utility parameters in PowerShell.
    # Given the nature of native completion results, you may find this works best with PSReadLine's MenuComplete mode.
    # https://github.com/PowerShell/UnixCompleters
    Import-Module PSUnixTabCompletion
}

# Set Theme
# oh-my-posh --init --shell pwsh --config "$HOME\Themes\PowerShell\Arch_Theme.omp.json" | Invoke-Expression
# oh-my-posh --init --shell pwsh --config "$env:POSH_THEMES_PATH/deadlydog.omp.json" | Invoke-Expression

oh-my-posh --init --shell pwsh --config "$env:POSH_THEMES_PATH/Arch_Theme.omp.json" | Invoke-Expression

# oh-my-posh init pwsh --config 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/jandedobbeleer.omp.json' | Invoke-Expression

# Aliases
# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/set-alias
Set-Alias -Name clearDNS -Value Clear-DnsClientCache
Set-Alias -Name flushDNS -Value Clear-DnsClientCache
Set-Alias -Name pshelp -Value Get-PSReadLineKeyHandler

# Test Command Existence
function Test-CommandExists {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        $command
    )
    $exists = $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
    return $exists
}

if (Test-CommandExists code) {
    Set-Alias -Name vscode -Value code
    function Edit-Profile { code $PROFILE }
} else {
    function Edit-Profile { micro $PROFILE }
}

function pfhelpfull {Get-PSReadLineKeyHandler -Bound -Unbound}

# Profile management
function reload { & $PROFILE }
$ProfileDirectory = $profile | split-path -Parent

# Navigation Shortcuts
function documents { Set-Location -Path $HOME\Documents }
function desktop { Set-Location -Path $HOME\Desktop }

# Useful shortcuts for traversing directories
function ..  { Set-Location .. }
function ...  { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# Enhanced Listing
function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }
function ll { Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize }

function admin {
    if($IsLinux -or $IsMacOS) {
        throw "This function only supports Windows Terminal"
    }
    if ($args.Count -gt 0) {
        $argList = "& '$args'"
        Start-Process wt -Verb runAs -ArgumentList "pwsh.exe -NoExit -Command $argList"
    } else {
        Start-Process wt -Verb runAs
    }
}

function Test-Elevation {
    # Check Administrator priviledges manually
    # ($NULL -eq $IsWindows) checks for Windows Sandbox enviroment
    if($IsWindows -or ($NULL -eq $IsWindows)) {
        # Get the ID and security principal of the current user account
        $myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
        $myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)
        # Get the security principal for the Administrator role
        $adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator

        return $myWindowsPrincipal.IsInRole($adminRole)
    } else {
        if($IsLinux -or $IsMacOS) {
            return ((id -u) -eq 0)
        } else {
            return $NULL
        }
    }
}

# Open PowerShell command history file
function Open-HistoryFile {
    code (Get-PSReadLineOption | Select-Object -ExpandProperty HistorySavePath)
}
Set-Alias -Name history -Value Open-HistoryFile -Option AllScope

# Copy the last command entered
function Copy-LastCommand {
    Get-History -Id $(((Get-History) | Select-Object -Last 1 |
          Select-Object ID -ExpandProperty ID)) |
        Select-Object -ExpandProperty CommandLine |
          clip
}

# Compute file hashes - useful for checking successful downloads
function Get-FileHash256 {
    $filePath = $args[0]
    $sha_256_hash = (Get-FileHash -Algorithm SHA256 $filePath).hash
    Write-Output "Hash for '$filePath' is '$sha_256_hash' (copied to clipboard)."
    $sha_256_hash | clip
}

# Get my external IP
function Get-ExternalIp {(Invoke-WebRequest http://ifconfig.me/ip).Content}
Set-Alias -Name myip -Value Get-ExternalIp -Description "Return external IP"

# Function to test internet connectivity
function Test-InternetConnection {
    try {
        Test-Connection -ComputerName 1.1.1.1 -Count 1 -ErrorAction Stop
        Write-Host "✅ Internet Connection available" -ForegroundColor DarkGreen
        return $True
    }
    catch {
        Write-Warning "⚠️ Internet connection is not available."
        return $False
    }
}

function uptime {
    net statistics workstation | Select-String "since" | ForEach-Object { $_.ToString().Replace('Statistics since ', '') }
}

# Quick File Creation
function newfile { 
    # newfile test1.txt, test2.txt, test3.txt
    param (
        [Parameter(Mandatory)]
        $fileNames
    ) 
    foreach ($fileName in $fileNames) { 
        New-Item -ItemType "file" -Path . -Name $fileName 
    }
}

# Quick Directory Creation
function newdir { 
    # newdir test1, test2, test3 
    param (
        [Parameter(Mandatory)]
        $dirNames
    )
    foreach ($dirName in $dirNames) { 
        New-Item -ItemType "directory" -Path . -Name $dirName 
    }
}

# Find files recursively
function findfile($search) {
    Get-ChildItem -Recurse -ErrorAction SilentlyContinue *.* | Where-Object { $_.name -like "*$search*" }
}

#Find files recursively, including hidden
function findhfile($search) {
    Get-ChildItem -Recurse -Force -ErrorAction SilentlyContinue *.* | Where-Object { $_.name -like "*$search*" }
}

function unzip ($file) {
    Write-Output("Extracting", $file, "to", $pwd)
    $fullFile = Get-ChildItem -Path $pwd -Filter $file | ForEach-Object { $_.FullName }
    Expand-Archive -Path $fullFile -DestinationPath $pwd
}

function pkill($name) {
    Get-Process $name -ErrorAction SilentlyContinue | Stop-Process
}

function Expand-Error {
    param (
        $ErrorRecord = $Error[0]
    )

    Write-Host "Top error:" -ForegroundColor DarkRed
    $ErrorRecord | Format-List * -Force
    $ErrorRecord.InvocationInfo | Format-List *
    $Exception = $ErrorRecord.Exception
    Write-Host "-------------------------------------------------------`n"
    for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException)) {
        Write-Host "Inner error $i :" -ForegroundColor DarkRed
        $Exception | Format-List * -Force
        Write-Host "`n"
    }
}
