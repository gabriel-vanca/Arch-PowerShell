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

if ($IsLinux -or $IsMacOS) {
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
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] $command
    )
    $exists = $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
    return $exists
}

if (Test-CommandExists code) {
    Set-Alias -Name vscode -Value code
    function Edit-Profile { code $PROFILE }
}
else {
    function Edit-Profile { micro $PROFILE }
}

function pfhelpfull { Get-PSReadLineKeyHandler -Bound -Unbound }

# Profile management
$env:ProfileDirectory = $profile | split-path -Parent
function reload {

    if ($Verbose) {
        Write-Host "Refreshing PowerShell profile"
    }

    & $PROFILE

    # ($NULL -eq $IsWindows) checks for Windows Sandbox enviroment
    if ($IsWindows -or ($NULL -eq $IsWindows)) {

        if ($Verbose) {
            Write-Host "Refreshing the current Windows session environment variables."
        }

        # Expected path of the choco.exe file.
        $chocoInstallPath = "$Env:ProgramData/chocolatey/choco.exe"
        if ((Test-Path -path $chocoInstallPath) -and (Test-CommandExists choco) -and (Test-CommandExists Update-SessionEnvironment)) {
            # Make `refreshenv` available right away, by defining the $env:ChocolateyInstall
            # variable and importing the Chocolatey profile module.
            $env:ChocolateyInstall = Convert-Path "$((Get-Command choco).Path)\..\.."   
            Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
            Update-SessionEnvironment # refreshenv is an alias
        }
        else {
            if ($Verbose) {
                Write-Warning "Update-SessionEnvironment was not available. Enviroment variables not refreshed. Please restart terminal session."
            }
        }
    }
}

# Useful shortcuts for traversing directories
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# Enhanced Listing
function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }
function ll { Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize }

if ($IsWindows -or ($NULL -eq $IsWindows)) {
    # Navigation Shortcuts
    function documents { $dir = [Environment]::GetFolderPath("MyDocuments"); Write-Host $dir; Set-Location -Path $dir }
    function desktop { $dir = [Environment]::GetFolderPath("Desktop"); Write-Host $dir; Set-Location -Path $dir }
    function startup { $dir = [Environment]::GetFolderPath("Startup"); Write-Host $dir; Set-Location -Path $dir }

    function Get-Elevation {
        [CmdletBinding()]
        [Alias('admin', 'elevate')]
        param()
        
        if ($IsLinux -or $IsMacOS -or (!(Test-CommandExists wt))) {
            throw "This function only supports Windows Terminal"
        }
        # if ($args.Count -gt 0) {
        #     $argList = "& '$args'"
        #     Start-Process wt -Verb runAs -ArgumentList "pwsh.exe -NoExit -Command $argList"
        # }
        # else {
            Start-Process wt -Verb runAs
        # }
    }
}

function Explore {
    param (
        [Parameter(Mandatory = $False)] $path = $NULL
    )
    if ($path) {
        if (!(Test-Path -Path $path)) {
            $path = Get-Location
            Write-Warning "Path is invalid. Browsing to current location."
        }
    }
    else {
        $path = Get-Location
    }
    Invoke-Item $path
}

function Test-Elevation {
    # Check Administrator priviledges

    [OutputType([System.Boolean])]
    [CmdletBinding()]
    [Alias('Test-Administrator', 'IsAdmin', 'Test-Admin' , 'IsAdministrator')]
    param()

    # ($NULL -eq $IsWindows) checks for Windows Sandbox enviroment
    if ($IsWindows -or ($NULL -eq $IsWindows)) {
        # Get the ID and security principal of the current user account
        $myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)
        # Get the security principal for the Administrator role
        $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator

        return $myWindowsPrincipal.IsInRole($adminRole)
    }
    else {
        if ($IsLinux -or $IsMacOS -or ($PSVersionTable.Platform -eq 'Unix')) {
            Write-Verbose "Running on Unix, checking if user is root."
            return ((id -u) -eq 0)
        }
        else {
            return $NULL
        }
    }
}

Function Get-CurrentUser {
    # ($NULL -eq $IsWindows) checks for Windows Sandbox enviroment
    if ($IsWindows -or ($NULL -eq $IsWindows)) {
        return [Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
    else {
        if ($IsLinux -or $IsMacOS) {
            return whoami
            # Alternatives to whoami are id -u -n or logname
        }
        else {
            return $Env:USERDOMAIN + "\" + $env:USERNAME
        }
    }
}

# Open PowerShell command history file
function Open-HistoryFile {
    [CmdletBinding()]
    [Alias('history')]
    param()
    code (Get-PSReadLineOption | Select-Object -ExpandProperty HistorySavePath)
}

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
function Get-ExternalIp { 
    [CmdletBinding()]
    [Alias('myip')]
    param( [Switch][Parameter(Mandatory = $false, Position = 0)] $FullInfo )

    if($FullInfo) { Invoke-RestMethod http://ipinfo.io/ -Headers @{'Accept' = 'application/json' } }

    return (Invoke-WebRequest http://ifconfig.me/ip).Content 
}

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
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] $fileNames
    ) 
    foreach ($fileName in $fileNames) { 
        New-Item -ItemType "file" -Path . -Name $fileName 
    }
}

# Quick Directory Creation
function newdir { 
    # newdir test1, test2, test3 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] $dirNames
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

function New-LogFilename ([string] $Path) { return ('{0}.{1}.log' -f $Path, (Get-Date -Format "yyyyMMddThhmmss")) }

function Expand-Error {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $False)] [ValidateNotNullOrEmpty()] $ErrorRecord = $Error[0]
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

function Measure-Script {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [ScriptBlock] $ScriptBlock
    )

    # https://www.powershellgallery.com/packages/Profiler/4.3.0
    if (!(Get-Module Profiler)) {
        if (Get-Module -Name Profiler -ListAvailable) {
            Import-Module -Name Profiler
        }
        else {
            throw "Profiler module not installed."
        }
    }

    # https://github.com/nohwnd/Profiler
    $trace = Trace-Script -ScriptBlock $ScriptBlock
    $trace.Top50SelfDuration | Out-GridView
}

# Source: https://gist.github.com/gabriel-vanca/51fdf312a70d57551fba0508729ebb86
function Invoke-CommandWithRetries {
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, HelpMessage = 'The script block to execute.')]
        [ValidateNotNullOrEmpty()]
        [scriptblock] $ScriptBlock,

        [Parameter(Position = 1, Mandatory = $false, HelpMessage = 'Number of times to retry the command. Default value is 5.')]
        [int] $RetryCount = 5,

        [Parameter(Position = 2, Mandatory = $false, HelpMessage = 'The time in milliseconds to pause and wait between each retry. Default is 5000.')]
        [int] $MillisecondsBetweenRetries = 5000,

        [Parameter(Position = 3, Mandatory = $false, HelpMessage = 'A list of error messages that should not be retried. If any part of the exception or error details match one of these messages, the script block will not be retried.')]
        [string[]] $ErrorMessagesToNotRetry = @()
    )
	
    begin { Write-Verbose "[$($MyInvocation.MyCommand.Name)] Function started" }
	
    process {
        [int] $currentAttemptIndex = 0

        do {
            try {
                $PreviousPreference = $ErrorActionPreference
                $ErrorActionPreference = 'Stop'
                Invoke-Command -ScriptBlock $ScriptBlock -OutVariable Result
                $ErrorActionPreference = $PreviousPreference
				
                # flow control will execute the next lines only if the command in the scriptblock executed without any errors
                # if an error is thrown, flow control will go to the 'catch' block
                Write-Verbose "Command completed successfully `n"
                # Break out of the while loop since the command succeeded.
                break
            } 
            catch {
                [string] $errorMessage = $_.Exception.ToString()
                [string] $errorDetails = $_.ErrorDetails
                Write-Verbose "[$($currentAttemptIndex + 1)/$($RetryCount + 1)] Failure to complete the task."
                Write-Verbose "Exception: $errorMessage"
                Write-Verbose "ErrorDetails: $errorDetails"

                if ($currentAttemptIndex -lt $RetryCount) {
                    foreach ($noRetryMessage in $ErrorMessagesToNotRetry) {
                        if ($errorMessage -like "*$noRetryMessage*" -or $errorDetails -like "*$noRetryMessage*") {
                            Write-Verbose "Found an error message that should not be retried. Aborting process..."
                            throw
                        }
                    }

                    Write-Verbose "Waiting $MillisecondsBetweenRetries milliseconds before trying again...`n"
                    Start-Sleep -Milliseconds $MillisecondsBetweenRetries
                }
                else {
                    Write-Verbose "All retry attempts depleted."
                    throw
                }
                $currentAttemptIndex++
            }
        } while ($true)
    }

    end { Write-Verbose "[$($MyInvocation.MyCommand.Name)] Complete" }
}

function Convert-ToBoolean {
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [string] $StringToConvert
    )

    switch -regex ($StringToConvert.Trim()) {
        '^(1|true|t|yes|y|on|enabled)$' { return $True }
        default { return $False }
    }
}

function Test-ObjectIsNullOrEmpty {
    <#
        .SYNOPSIS
        Test if an object is null or empty

        .DESCRIPTION
        Test if an object is null or empty

        .EXAMPLE
        '' | IsNullOrEmpty

        True
    #>
    [OutputType([bool])]
    [Cmdletbinding()]
    [Alias('IsNullOrEmpty')]
    param(
        # The object to test
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [AllowNull()]
        [object] $Object
    )

    try {
        if (-not ($PSBoundParameters.ContainsKey('Object'))) {
            Write-Debug "Object was never passed, meaning it's empty or null."
            return $true
        }
        if ($null -eq $Object) {
            Write-Debug 'Object is null'
            return $true
        }
        Write-Debug "Object is: $($Object.GetType().Name)"
        if ($Object -eq 0) {
            Write-Debug 'Object is 0'
            return $true
        }
        if ($Object.Length -eq 0) {
            Write-Debug 'Object is empty array or string'
            return $true
        }
        if ($Object.GetType() -eq [string]) {
            if ([string]::IsNullOrWhiteSpace($Object)) {
                Write-Debug 'Object is empty string'
                return $true
            }
            else {
                Write-Debug 'Object is not an empty string'
                return $false
            }
        }
        if ($Object.Count -eq 0) {
            Write-Debug 'Object count is 0'
            return $true
        }
        if (-not $Object) {
            Write-Debug 'Object evaluates to false'
            return $true
        }
        if (($Object.GetType().Name -ne 'PSCustomObject')) {
            Write-Debug 'Casting object to PSCustomObject'
            $Object = [PSCustomObject]$Object
        }
        if (($Object.GetType().Name -eq 'PSCustomObject')) {
            Write-Debug 'Object is PSCustomObject'
            if ($Object -eq (New-Object -TypeName PSCustomObject)) {
                Write-Debug 'Object is similar to empty PSCustomObject'
                return $true
            }
            if (($Object.psobject.Properties).Count | Test-IsNullOrEmpty) {
                Write-Debug 'Object has no properties'
                return $true
            }
        }
    }
    catch {
        Write-Debug 'Object triggered exception'
        return $true
    }

    Write-Debug 'Object is not null or empty'
    return $false
}

function Format-MacAddress {
    <#
    .SYNOPSIS
        Function to cleanup a MACAddress string
    .DESCRIPTION
        Function to clean up a MACAddress string and optionally format it with separators
    .PARAMETER MacAddress
        Specifies the MacAddress. Either a single string or an array of strings. Aliased to 'Address'
    .PARAMETER Separator
        Specifies the separator every X characters. Aliased to 'Delimiter'. Validated against set(':', 'None', '.', "-", ' ', 'Space', ';')
    .PARAMETER Case
        Specifies if the output is to be set in a particular case
        Upper Sets to upper case, 'a' becomes 'A'
        Uppercase Sets to upper case, 'a' becomes 'A'
        Lower Sets to lower case, 'A' becomes 'a'
        Lowercase Sets to lower case, 'A' becomes 'a'
        Ignore Does nothing to the case of the letters 'aB', so remains as 'aB'
    .Parameter Split
        Specifies how many characters to split the MacAddress on. Valid values are 2,3,4,6
    .EXAMPLE
        Format-MacAddress -MacAddress 1234567890ab
        12:34:56:78:90:ab
    .EXAMPLE
        Format-MacAddress -MacAddress '00:11:22:dD:ee:FF' -Case Upper
        00:11:22:DD:EE:FF
    .EXAMPLE
        Format-MacAddress -MacAddress '00:11:22:dD:ee:FF' -Case Lowercase
        001122ddeeff
    .EXAMPLE
        Format-MacAddress -MacAddress '00:11:22:dD:ee:FF' -Case Lowercase -Separator '-'
        00-11-22-dd-ee-ff
    .EXAMPLE
        Format-MacAddress -MacAddress '00:11:22:dD:ee:FF' -Case Lowercase -Separator '.'
        00.11.22.dd.ee.ff
    .EXAMPLE
        Format-MacAddress -Address '00:11:22:dD:ee:FF', '10005a123456' -case Uppercase -Delimiter '-'
        00-11-22-DD-EE-FF
        10-00-5A-12-34-56
     
        Showing how function can take an array of MacAddress using the alias 'Address' and the alias 'Delimiter' for the 'Separator' parameter
    .EXAMPLE
        '00:11:22:dD:ee:FF', '10005a123456' | Format-MacAddress -case Lowercase -Separator '.'
        00.11.22.dd.ee.ff
        10.00.5a.12.34.56
     
        Showing how the values for MacAddress can be received from the pipeline
    .EXAMPLE
        Format-MacAddress '10005a123456' -case Lowercase -Separator ':'
        10:00:5a:12:34:56
     
        Showing how MacAddress can be unnamed positional parameter
    .EXAMPLE
        '00:11:22:dD:ee:FF' | Format-MacAddress -Separator None -Case Ignore
     
        001122dDeeFF
    .EXAMPLE
        '00:11:22:dD:ee:FF', '10005a123456' | Format-MacAddress -case Lowercase -Separator '.' -Split 4
        0011.22dd.eeff
        1000.5a12.3456
    .EXAMPLE
        '00:11:22:dD:ee:FF', '10005a123456' | Format-MacAddress -case Lowercase -Separator '.' -Split 4 -IncludeOriginal
     
        OriginalMac FormattedMac
        ----------- ------------
        00:11:22:dD:ee:FF 0011.22dd.eeff
        10005a123456 1000.5a12.3456
    .EXAMPLE
        Format-MacAddress -MacAddress (Get-RandomMacAddress) -Separator '.'
     
        95.4a.e6.39.05.aa
    .OUTPUTS
        System.String
    
    #>
    
    #region Parameter
    [OutputType('String')]
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0, HelpMessage = 'Please enter a MAC address (12 hex)', Mandatory, ValueFromPipeline)]
        [Alias('Address')]
        [String[]] $MacAddress,
    
        [ValidateSet(':', 'None', '.', '-', ' ', 'Space', ';')]
        [Alias('Delimiter')]
        [string] $Separator = ':',
    
        [ValidateSet('Ignore', 'Upper', 'Uppercase', 'Lower', 'Lowercase')]
        [string] $Case = 'Upper',
    
        [ValidateSet(2, 3, 4, 6)]
        [int] $Split = 2,
    
        [switch] $IncludeOriginal
    )
    
    begin {
        if ($Separator -eq 'Space') { $Separator = ' ' }
        Write-Verbose -Message "Starting [$($MyInvocation.Mycommand)]"
    }
    
    process {
        foreach ($Mac in $MacAddress) {
            $oldMac = $Mac
            $Mac = $Mac -replace '-', '' #Replace Dash
            $Mac = $Mac -replace ':', '' #Replace Colon
            $Mac = $Mac -replace ';', '' #Replace semicolon
            $Mac = $Mac -replace '/s', '' #Remove whitespace
            $Mac = $Mac -replace ' ', '' #Remove whitespace
            $Mac = $Mac -replace '\.', '' #Remove dots
            $Mac = $Mac.trim() #Remove space at the beginning
            $Mac = $Mac.trimend() #Remove space at the end
            switch ($Case) {
                'Upper' { $Mac = $mac.toupper() }
                'Uppercase' { $Mac = $mac.toupper() }
                'Lower' { $Mac = $mac.tolower() }
                'Lowercase' { $Mac = $mac.tolower() }
                'Ignore' { }
                Default { }
            }
    
            if ($Separator -ne 'None') {
                switch ($Split) {
                    2 { $Mac = $Mac -replace '(..(?!$))', "`$1$Separator" }
                    3 { $Mac = $Mac -replace '(...(?!$))', "`$1$Separator" }
                    4 { $Mac = $Mac -replace '(....(?!$))', "`$1$Separator" }
                    6 { $Mac = $Mac -replace '(......(?!$))', "`$1$Separator" }
                    default { $Mac = $Mac -replace '(..(?!$))', "`$1$Separator" }
                }
            }
    
            if ( -not ($IncludeOriginal) ) {
                write-output -InputObject $Mac
            }
            else {
                $prop = ([ordered] @{ OriginalMac = $oldMac ; FormattedMac = $mac })
                $obj = new-object -TypeName psobject -Property $prop
                write-output -InputObject $obj
            }
        }
    } #EndBlock Process
    
    end {
        Write-Verbose -Message "Ending [$($MyInvocation.Mycommand)]"
    }
    
} #EndFunction Format-MacAddress

function Format-RandomCase {
    <#
    .SYNOPSIS
        Formats a string character by character randomly into upper or lower case.
    .DESCRIPTION
        Formats a string character by character randomly into upper or lower case.
    .PARAMETER String
        A [string[]] that you want formatted randomly into upper or lower case
    .EXAMPLE
        Format-RandomCase -String 'HELLO WORLD IT IS ME!'
     
        Example return
        HelLo worlD It is me!
    #>
        
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [string[]] $String
    )
    
    foreach ($currentString in $String) {
        $CharArray = [char[]] $currentString
        $CharArray | ForEach-Object 
        {
            $Random = 0, 1 | Get-Random
            if ($Random -eq 0) {
                $ReturnVal += ([string] $_).ToLower()
            }
            else {
                $ReturnVal += ([string] $_).ToUpper()
            }
        }

        Write-Output -InputObject $ReturnVal
    }
}

function Invoke-Monitor {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]$Hostname,
        [Parameter(Mandatory = $false)]$Port = 80,
        [Parameter(Mandatory = $false)]$Seconds = 3
    )

    function NoMili{

        [CmdletBinding()]
        Param (
            [Parameter(Mandatory = $true)] [system.diagnostics.stopwatch] $stopwatch
        )

        $ts = $stopwatch.Elapsed
        return "{0:00}:{1:00}:{2:00}.{3:00}" -f $ts.Hours, $ts.Minutes, $ts.Seconds, ($ts.Milliseconds / 10)
    }

    $currentAttempt = 0;
    #Start Stopwatch
    $stopwatch = [system.diagnostics.stopwatch]::StartNew()

    while($true) {
        $currentAttempt++;
        #Test connection and Sleep
        $success = Test-NetConnection -ComputerName $Hostname -Port $Port -InformationLevel Quiet -WarningAction 'SilentlyContinue'
        if($success) {
            break
        }

        Start-Sleep -Seconds $seconds
        #Write fail status and time elapsed
        Write-Host "[$currentAttempt] Elapsed Time $(NoMili($stopwatch)) " -ForegroundColor Green -NoNewline
        Write-Host "Server failed to connect `n" -BackgroundColor black -ForegroundColor Red
    }

    #Reset the stopwatch
    $stopwatch.Stop()
    $stopwatch.Reset()

    #Write about success and play music
    Write-Host "SUCCESS: Successful connection to $($Hostname):$($Port) after $currentAttempt attempts and $(NoMili($stopwatch)) time elapsed" -ForegroundColor Green;
}

if ($IsWindows -or ($NULL -eq $IsWindows)) {

    function Lock-Workstation {
        <#
        .SYNOPSIS
            Locks the workstation
        .DESCRIPTION
            Locks the workstation and requires authentication afterwards
        .EXAMPLE
            Lock-Workstation
        #>

        [CmdletBinding()]
        [Alias('lock')]
        param()
        
        Write-Output "Locking workstation at: $((Get-Date).ToString())"
        rundll32.exe user32.dll,LockWorkStation
    }

    Function Get-UserProfiles {
        <#
            .SYNOPSIS
                Gets all of the user profiles on the system.
        #>
        
        Write-Output -InputObject (Get-WmiObject -Class Win32_UserProfile | Where-Object { $_.Special -eq $false } | Select-Object -ExpandProperty LocalPath)

    }

    function Repair-Windows {
        [CmdletBinding()]
        [Alias('repair-system')]
        param (
            [Switch] $DriveCheck
        )

        if(!Test-Elevation) {
            throw "This script must be run as an administrator."
        }

        Write-Host "The Deployment Image Servicing and Management is a command-line tool that allows administrators to prepare, modify, and repair system images" -ForegroundColor DarkGreen
        # The DISM command tool includes three options to repair an image, including "CheckHealth," "ScanHealth," and "RestoreHealth," which you want to use in this order.
    
        Write-Host "The CheckHealth option with the DISM tool allows you to determine any corruptions inside the local Windows image." -ForegroundColor DarkGreen
        Write-Host "However, the option does not perform any repairs."
        Write-Host "Deployment Image Servicing and Management tool will run and verify any data corruption that may require fixing.`n" -ForegroundColor DarkGreen
        DISM /Online /Cleanup-Image /CheckHealth

        Write-Host "The ScanHealth option does a more advanced scan to find out whether the image has any problems." -ForegroundColor DarkGreen
        Write-Host "ScanHealth also repairs and restores health of Windows image.`n" -ForegroundColor DarkGreen
        DISM /Online /Cleanup-Image /ScanHealth

        Write-Host "If there are problems with the system image, use DISM with the RestoreHealth option to automatically scan and repair common issues." -ForegroundColor DarkGreen
        Write-Host "⚠️ If the command appears stuck, this is in fact normal behaviour. After a few minutes, the process will complete successfully.`n" -ForegroundColor DarkYellow
        DISM /Online /Cleanup-Image /RestoreHealth
    
        Write-Host "After restoring the image to a healthy state using DISM, one should use the System File Checker (SFC) command tool to repair the current setup.`n"

        Write-Host "System File Checker (SFC) is a command-line tool designed to scan the integrity and restore missing or corrupted system files with working replacements.`n" -ForegroundColor DarkGreen

        #Clear log
        $sfc_logFile = $ENV:SystemDrive + "\Windows\Logs\CBS\CBS.log"
        if(Test-Path $sfc_logFile) {
            Remove-Item -Path $sfc_logFile -Force -ErrorAction SilentlyContinue
        }

        sfc /scannow

        if(Test-Path $sfc_logFile) {
            # Prepare log
            $File = New-TemporaryFile
            findstr /c:"[SR]" $sfc_logFile > $File
        }

        Write-Host ""
        Write-Host "SFC scan completed." -ForegroundColor DarkGreen
        Write-Host "Logs are available at: $($File.toString())" -ForegroundColor DarkYellow

        if(Test-CommandExists code) {
            code $File
        } else {
            if (Test-CommandExists micro) {
                micro $File
            } else {
                notepad $File
            }
        }

        Write-Host "⚠️ If you get a 'Windows Resource Protection could not perform the requested operation' error, this indicates a problem during the scan, and an offline scan is required. You will have to reboot into recovery mode and run SFC offline.`n" -ForegroundColor DarkYellow

        Write-Host "⚠️ If you get a 'Windows Resource Protection found corrupt files but was unable to fix some of them. Details are included in the CBS.Log' error, this indicates you may need to repair the corrupted files manually. You will need to manually repair them.`n" -ForegroundColor DarkYellow

        Write-Host "⚠️ If all else fails, another option you might want to consdier is System Restore.`n" -ForegroundColor DarkYellow
        rstrui.exe

        if(!$DriveCheck) {
            return
        }
        
        Write-Host "ChkDsk is a tool that checks the file system and file system metadata of a volume for logical and physical errors.`n" -ForegroundColor DarkGreen

        # Marks volume C as a dirty (corrupt) volume by setting the dirty bit of the volume
        fsutil dirty set $ENV:SystemDrive
        # all volumes are checked when the computer is started and all dirty volumes get chkdsk to run on them
        chkntfs /d

        Write-Host ""
        Write-Host "⚠️ System drive is now marked for repair at computer restart. ⚠️`n" -ForegroundColor DarkRed
        Write-Host "⚠️ Please restart as soon as possible. ⚠️`n" -ForegroundColor DarkRed
        Write-Host "⚠️ Interrupting chkdsk is not recommended. However, canceling or interrupting chkdsk should not leave the volume any more corrupt than it was before chkdsk was run. Running chkdsk again checks and should repair any remaining corruption on the volume.`n" -ForegroundColor DarkYellow
        Write-Host "⚠️ Chkdsk logs will be available at: Event Viewer > Windows Logs > Application > Filter Current Log > Event Sources > CHKDSK and Wininit > OK" -ForegroundColor DarkYellow
    }

    Function Get-LocalGroupMembers {
        <#
            .SYNOPSIS
                Gets the members of a local group
     
            .DESCRIPTION
                This cmdlet gets the members of a local group on the local or a remote system. The values are returned as DirectoryEntry values in the format WinNT://Domain/Name.
     
            .PARAMETER LocalGroup
                The local group on the computer to enumerate.
     
            .PARAMETER ComputerName
                The name of the computer to query. This defaults to the local computer.
     
            .EXAMPLE
                Get-LocalGroupMembers -LocalGroup Administrators
     
                Gets the membership of the local administrators group on the local machine.
     
        #>  
        [CmdletBinding()]
        [OutputType([System.String[]])]
        Param(
            [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
            [ValidateNotNullOrEmpty()]
            [System.String]$LocalGroup,        
    
            [Parameter(Position = 1)]
            [ValidateNotNullOrEmpty()]
            [System.String]$ComputerName = $env:COMPUTERNAME
        )
    
        $Group = [ADSI]"WinNT://$ComputerName/$LocalGroup,group"    
                                        
        $Members = $Group.Invoke("Members", $null) | Select-Object @{Name = "Name"; Expression = { $_[0].GetType().InvokeMember("ADSPath", "GetProperty", $null, $_, $null) } } | Select-Object -ExpandProperty Name                
    
        Write-Output -InputObject $Members
    }

    

    Function Test-RegistryKeyProperty {
        <#
        .SYNOPSIS
            Tests the existence of a registry value
 
        .DESCRIPTION
            The Test-RegistryKeyProperty cmdlet test the extistence of a registry value (property of a key).
 
        .PARAMETER Key
            The registry key to test for containing the property.
 
        .PARAMETER PropertyName
            The property name to test for.
 
        .EXAMPLE
            Test-RegistryKeyProperty -Key "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Component Based Servicing" -PropertyName PendingFileRenameOperations
             
            Returns true or false depending on the existence of the property
 
        .OUTPUTS
            System.Boolean
    #>

        [CmdletBinding()]
        [OutputType([System.Boolean])]
        Param (
            [Parameter(Position = 0, Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [System.String]$Key,

            [Parameter(Position = 1, Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [System.String]$PropertyName
        )

        if ($IsWindows -or ($NULL -eq $IsWindows)) {

            if (!(Test-Path -Path $Key)) {
                return $False
            }
            Get-ItemProperty -Path $Key -Name $PropertyName -ErrorAction SilentlyContinue | Out-Null
            Write-Output -InputObject $?
        }
        else {
            throw "This function only supports Windows"
        }
    }

    function Get-RegistryEntries {
        <#
        .SYNOPSIS
            Gets all of the properties and their values associated with a registry key.
 
        .DESCRIPTION
            The Get-RegistryEntries cmdlet gets each entry and its value for a specified registry key.
            The intended use of this cmdlet is to supplement the Get-ItemProperty cmdlet to get the values for every entry in a registry key.
 
        .PARAMETER Path
            The registry key path in the format that PowerShell can process, such as HKLM:\Software\Microsoft or Registry::HKEY_LOCAL_MACHINE\Software\Microsoft
 
        .INPUTS
            System.String
 
                You can pipe a registry path to Get-RegistryEntries.
 
        .OUTPUTS
            System.Management.Automation.PSCustomObject[]
 
        .EXAMPLE
            Get-RegistryEntries -Path HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall
 
            Gets all of the entries associated with the registry key. It does not get any information about subkeys.
            
    #>

        [CmdletBinding()]
        [OutputType([System.Management.Automation.PSCustomObject[]])]
        Param(
            [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
            [ValidateScript({
                    Test-Path -Path $_
                })]
            [ValidateNotNullOrEmpty()]
            [System.String]$Path
        )

        if ($IsWindows -or ($NULL -eq $IsWindows)) {
            Get-Item -Path $Path | Select-Object -ExpandProperty Property | ForEach-Object {
                Write-Output -InputObject ([PSCustomObject]@{"Path" = $Path; "Property" = "$_"; "Value" = (Get-ItemProperty -Path $Path -Name $_ | Select-Object -ExpandProperty $_) })
            }
        }
        else {
            throw "This function only supports Windows"
        }
    }

    function Move-ToRecycleBin {
        <#
    .SYNOPSIS
        Instead of outright deleting a file, why not move it to the Recycle Bin?
    .DESCRIPTION
        Instead of outright deleting a file, why not move it to the Recycle Bin?
        Function aliased to 'Recycle'
    .PARAMETER Path
        A string or array of strings representing a file or a folder. Wildcards are
        acceptable and will be resolved to specific file or folder names. Can accept
        values from the pipeline.
    .EXAMPLE
        Move-ToRecycleBin -Path c:\temp\dummyfile.txt -Verbose
     
        VERBOSE: Moving 'c:\temp\dummyfile.txt' to the Recycle Bin
    .EXAMPLE
        Move-ToRecycleBin -Path c:\temp\dummyfile2.txt
     
        Moves c:\temp\dummyfile2.txt to the Recycle Bin

    .EXAMPLE
        "./email.pdf" | Move-ToRecycleBin 
     
        Pipeline is supported.
    .EXAMPLE
        Move-ToRecycleBin .\FileDoesNotExist
     
        Move-ToRecycleBin : ERROR: Path [.\FileDoesNotExist] does not exist
    .EXAMPLE
        Move-ToRecycleBin -Path 'File1.txt', 'File2.txt'
     
        Moves both File1.txt and File2.txt to the Recycle Bin
    #>
    
        [CmdletBinding(ConfirmImpact = 'Medium')]
        [alias('Recycle')]
        param (
            [Parameter(Mandatory, HelpMessage = 'Please enter a path to a file or folder. Wildcards accepted.', ValueFromPipeline, ValueFromPipelineByPropertyName)]
            [string[]] $Paths
        )
    
        begin {
            if ($IsWindows -or ($NULL -eq $IsWindows)) {
                $FileSystem = New-Object -TypeName 'Microsoft.VisualBasic.FileIO.FileSystem'
                Write-Verbose -Message "Starting [$($MyInvocation.MyCommand)]"
            }
            else {
                throw "This function only supports Windows"
            }
        }
    
        process {

            # $ErrorList = @()

            foreach ($currentPath in $Paths) {
                if (Test-Path -Path $currentPath) {
                    $File = Resolve-Path -Path $currentPath
                    foreach ($currentFile in $File) {
                        Write-Verbose "Moving '$currentFile' to the Recycle Bin"
                        
                        try {
                            if (Test-Path -Path $currentFile -PathType Container) {
                                $FileSystem::DeleteDirectory($currentFile, 'OnlyErrorDialogs', 'SendToRecycleBin')
                            }
                            else {
                                $FileSystem::DeleteFile($currentFile, 'OnlyErrorDialogs', 'SendToRecycleBin')
                            }
                        }
                        catch {
                            # ErrorList += @{ 'Path' = $currentPath; 'Error' = $_ }
                            Write-Error ("ERROR at " + $currentPath + " : " + $_)
                        }
                    }
                }
                else {
                    Write-Warning -Message "Path [$currentPath] does not exist. Skipping item deletion."
                }
            }
        }
    
        end {
            Remove-Variable -Name FileSystem
            Write-Verbose -Message "Ending [$($MyInvocation.MyCommand)]"
        }
    }
}
