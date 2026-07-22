<#
.SYNOPSIS
    Reads the parameters (public properties) an MSI package exposes, reporting each property's
    default value and, where the package's install UI defines one, a human-readable description.

.DESCRIPTION
    An MSI can be driven from the msiexec command line by setting its public properties
    (PROPERTY=VALUE). This script surfaces those parameters without installing anything: it opens
    the package read-only and reads several of its tables.

      - Property           : properties and their authored default value. A silent install (what
                             winget performs) uses these defaults unless overridden on the command line.
      - CheckBox           : the on/off install toggles. These are usually the interesting parameters
                             (add to PATH, register manifest, context menus, ...) and most carry NO
                             Property-table row, so a Property-only reader misses them entirely.
      - CustomAction       : SetProperty actions (base type 51) that set a toggle's fresh-install
                             default. For a CheckBox toggle absent from the Property table, its Default
                             is derived from these: '1' when an action defaults it on, '0' when one
                             defaults it off, and blank (unknown) when no literal setter is found.
      - SecureCustomProperties : the subset of public properties an unprivileged/UAC-elevated managed
                             install is allowed to set. Reported as the "Secure" flag.
      - Control / RadioButton  : the install UI. MSIs carry no free-form property documentation, so a
                             parameter's "Description" is best-effort: the label of the checkbox or
                             radio option wired to it, when the package has a UI.

    Each row shows Property Name, Default Value, Source, Description, and Secure. A property is public
    (settable on the command line) when its name has no lowercase letters - Windows Installer's own rule.
    Non-public properties are hidden by default except a small kept set (product identity and the WiX UI
    wiring), shown with predefined descriptions. Only properties the package actually authors are printed;
    a kept name the package omits is not shown. A leading Prv column flags non-public properties.

    The Source explains where the Default Value comes from, which is important:
      - Property : the Default Value is the EXACT value authored in the package's Property table.
      - CheckBox : the Default Value is DERIVED from the package's SetProperty custom actions by a static
                   heuristic - the script scans those actions for a literal 0 or 1 assigned to the property
                   and does NOT evaluate their run order or conditions. It reflects the common fresh-install
                   default and can differ for packages whose defaults are set by richer conditions.

    Output is printed as a table by default, or as a list with -List. With -PrintReport the same content is
    also written to a .txt next to the .msi (or to the Desktop when the source is a -Url download in TEMP,
    or to -ReportOutputPath when given).

    The MSI is supplied in one of three ways (see the parameter sets): a full path, a file name
    resolved against this script's own directory, or a URL downloaded to $env:TEMP first.

.PARAMETER Path
    Full path to a local .msi file to read.

.PARAMETER Name
    File name of a .msi located in the same directory as this script.

.PARAMETER Url
    URL of a .msi to download to $env:TEMP and read. The download is deleted afterward unless
    -ReuseArtifacts is supplied. -Name and -Path files are always left untouched.

.PARAMETER PublicOnly
    Report only public properties, i.e. those settable on the msiexec command line.

.PARAMETER ReuseArtifacts
    Applies to -Url. Look in $env:TEMP first and reuse an existing copy of the package instead of
    re-downloading, and keep the downloaded file afterward instead of deleting it. Useful when iterating
    so a large package is fetched only once.

.PARAMETER List
    Print each parameter as a property list instead of the default table.

.PARAMETER PrintReport
    Also write the report to a .txt file named <msi file name>.msi.ParamAnalysis.txt, overwriting any
    existing file of that name. By default it is written next to the .msi; for a -Url download (which
    lives in $env:TEMP) it is written to the Desktop instead. -ReportOutputPath overrides the location.

.PARAMETER ReportOutputPath
    Overrides where -PrintReport writes. A value ending in .txt is the full destination file; any other
    value is treated as a directory the standard-named report is placed in. Implies -PrintReport.

.OUTPUTS
    None. The report is printed to the host (and optionally written to a file); the script does not emit
    objects to the pipeline.

.EXAMPLE
    .\Read-MsiParameters.ps1 -Url 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.4/PowerShell-7.6.4-win-x64.msi'

.EXAMPLE
    .\Read-MsiParameters.ps1 -Url 'https://.../Some.msi' -ReuseArtifacts   # keep the download for re-runs

.EXAMPLE
    .\Read-MsiParameters.ps1 -Path 'C:\packages\Some.msi' -List -PrintReport

.EXAMPLE
    .\Read-MsiParameters.ps1 -Name 'PowerShell-7.6.4-win-x64.msi'
#>
[CmdletBinding(DefaultParameterSetName = 'Path')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path')]
    [string]$Path,

    [Parameter(Mandatory, ParameterSetName = 'Name')]
    [string]$Name,

    [Parameter(Mandatory, ParameterSetName = 'Url')]
    [string]$Url,

    [switch]$PublicOnly,

    [switch]$ReuseArtifacts,

    [switch]$List,

    [switch]$PrintReport,

    [string]$ReportOutputPath
)

# ---- COM helpers ----------------------------------------------------------
# The WindowsInstaller.Installer automation object is reached through late binding. Two binding paths
# exist and they are NOT interchangeable here: COM *methods* (OpenDatabase, OpenView, Execute, Fetch,
# Close) must be called with PowerShell dot syntax, which coerces the arguments from the IDispatch
# type info; calling them through Type.InvokeMember(...InvokeMethod...) throws DISP_E_TYPEMISMATCH
# (the raw binder passes the mode/record arguments with the wrong VARIANT type). COM *property* reads
# are the opposite: Record.StringData is an indexed property and Record.FieldCount does not surface as
# a plain member, so both are read through Type.InvokeMember(...GetProperty...), which is reliable.
function Get-MsiComProperty {
    param($ComObject, [string]$MemberName, $Arguments = $null)
    $ComObject.GetType().InvokeMember($MemberName, [System.Reflection.BindingFlags]::GetProperty, $null, $ComObject, $Arguments)
}

# Reads a whole MSI table as an array of string-field arrays. Returns an empty array when the table
# does not exist (OpenView throws for an unknown table), which lets optional UI tables be absent.
function Read-MsiTable {
    param($Database, [string]$Query)

    try {
        $view = $Database.OpenView($Query)
    }
    catch {
        return , @()
    }
    # Execute and Close emit a null return value through the COM/IDispatch layer; left unsuppressed it
    # lands in the function's output stream and corrupts the returned row set. [void] discards it.
    [void]$view.Execute()

    $rows = [System.Collections.Generic.List[object]]::new()
    while ($true) {
        $record = $view.Fetch()
        if ($null -eq $record) {
            break
        }
        $fieldCount = Get-MsiComProperty $record 'FieldCount'
        $fields = for ($fieldIndex = 1; $fieldIndex -le $fieldCount; $fieldIndex++) {
            Get-MsiComProperty $record 'StringData' @($fieldIndex)
        }
        $rows.Add(@($fields))
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($record)
    }

    [void]$view.Close()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($view)
    , $rows.ToArray()
}

# UI label text carries MSI formatting: {\Font} / {...} style tokens and & keyboard accelerators.
# Strip them and flatten whitespace so the label reads as a plain one-line description.
function ConvertTo-CleanLabel {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }
    ($Text -replace '\{\\[^}]*\}', '' -replace '[{}]', '' -replace '&', '' -replace '\s+', ' ').Trim()
}

# The interesting install options are usually toggles that carry NO row in the Property table: the
# package leaves them undefined and picks a fresh-install default with a SetProperty custom action
# (base type 51 - msidbCustomActionTypeProperty - which the deferred 307 variant also reduces to).
# This derives that default from those actions: a literal Target of '1' means the option defaults on;
# when the only literal setter found is '0' it defaults off; anything else is left unknown (empty).
# $SetPropertyActions is an array of @(SourceProperty, Target) pairs, already filtered to base type 51.
function Get-CustomActionDefault {
    param([string]$Property, $SetPropertyActions)

    $literals = foreach ($action in $SetPropertyActions) {
        if ($action[0] -eq $Property) { $action[1] }
    }
    if ($literals -contains '1') {
        return '1'
    }
    if ($literals -contains '0') {
        return '0'
    }
    return ''
}

# ---- MSI source resolution ------------------------------------------------
# Turns whichever parameter set was used into the .msi to read, settling the package's provenance in one
# place. Returns @{ Path; IsTemporaryLocation; DeleteAfterUse }: IsTemporaryLocation is $true for a -Url
# package living in $env:TEMP (which routes the report to the Desktop), and DeleteAfterUse is $true only
# for a URL fetched this run without -ReuseArtifacts (a -Name/-Path file or a reused/kept download is
# never a throwaway). -ReuseArtifacts looks in $env:TEMP first and skips the download when the package is
# already there; without it a URL is always fetched fresh.
function Resolve-MsiPath {
    param([string]$ParameterSetName, [string]$Path, [string]$Name, [string]$Url, [string]$ScriptDirectory, [bool]$ReuseArtifacts)

    if ($ParameterSetName -eq 'Url') {
        $fileName = [System.IO.Path]::GetFileName(([System.Uri]$Url).LocalPath)
        if ([string]::IsNullOrWhiteSpace($fileName)) {
            $fileName = 'downloaded.msi'
        }
        $destination = Join-Path $env:TEMP $fileName
        if ($ReuseArtifacts -and (Test-Path -LiteralPath $destination) -and (Get-Item -LiteralPath $destination).Length -gt 0) {
            Write-Host "Reusing already-downloaded package: $destination" -ForegroundColor DarkYellow
            return @{ Path = $destination; IsTemporaryLocation = $true; DeleteAfterUse = $false }
        }
        Write-Host "Downloading $Url" -ForegroundColor Yellow
        Write-Host "  to $destination" -ForegroundColor Yellow
        # TLS 1.2 is not in the default set on Windows PowerShell 5.1; GitHub requires it. Progress
        # rendering makes Invoke-WebRequest crawl on 5.1, so it is silenced for the transfer.
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        $previousProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $Url -OutFile $destination -UseBasicParsing -ErrorAction Stop
        }
        finally {
            $ProgressPreference = $previousProgress
        }
        return @{ Path = $destination; IsTemporaryLocation = $true; DeleteAfterUse = (-not $ReuseArtifacts) }
    }

    $resolved = if ($ParameterSetName -eq 'Name') { Join-Path $ScriptDirectory $Name } else { $Path }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "MSI not found: $resolved"
    }
    @{ Path = (Resolve-Path -LiteralPath $resolved).Path; IsTemporaryLocation = $false; DeleteAfterUse = $false }
}

# Decides where the report .txt is written. The file is always named <msi file name>.msi.ParamAnalysis.txt.
# Default: beside the .msi, or the Desktop when the .msi sits in throwaway $env:TEMP. An explicit
# -ReportOutputPath overrides both: a value ending in .txt is the full destination, anything else is
# treated as a directory to drop the standard-named file into.
function Resolve-ReportPath {
    param([string]$MsiPath, [bool]$MsiInTemporaryLocation, [string]$ReportOutputPath)

    $reportFileName = "$(Split-Path -Leaf $MsiPath).ParamAnalysis.txt"

    if ($ReportOutputPath) {
        $destination = if ([System.IO.Path]::GetExtension($ReportOutputPath) -eq '.txt') { $ReportOutputPath }
        else { Join-Path $ReportOutputPath $reportFileName }
        $directory = Split-Path -Parent $destination
        if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        return $destination
    }

    $directory = if ($MsiInTemporaryLocation) { [Environment]::GetFolderPath('Desktop') } else { Split-Path -Parent $MsiPath }
    Join-Path $directory $reportFileName
}

# ---- Main -----------------------------------------------------------------
# COM automation for MSI databases exists on Windows only.
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
    throw 'Read-MsiParameters reads Windows Installer packages and runs on Windows only.'
}

$resolvedMsi = Resolve-MsiPath -ParameterSetName $PSCmdlet.ParameterSetName -Path $Path -Name $Name -Url $Url -ScriptDirectory $PSScriptRoot -ReuseArtifacts $ReuseArtifacts
$msiPath = $resolvedMsi.Path

$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $null
try {
    # 0 = msiOpenDatabaseModeReadOnly: never modifies the package.
    $database = $installer.OpenDatabase($msiPath, 0)

    # Identifiers are backtick-quoted for MSI SQL; the query strings are single-quoted so PowerShell
    # leaves the backticks alone.
    # The Control table is filtered to CheckBox rows in MSI SQL: it is the largest UI table, and every
    # fetched row pays several late-bound COM calls only to be discarded otherwise.
    $propertyRows = Read-MsiTable $database 'SELECT `Property`, `Value` FROM `Property`'
    $checkBoxRows = Read-MsiTable $database 'SELECT `Property`, `Value` FROM `CheckBox`'
    $checkBoxControlRows = Read-MsiTable $database 'SELECT `Property`, `Text` FROM `Control` WHERE `Type`=''CheckBox'''
    $radioRows = Read-MsiTable $database 'SELECT `Property`, `Value`, `Text` FROM `RadioButton`'
    $customActionRows = Read-MsiTable $database 'SELECT `Source`, `Target`, `Type` FROM `CustomAction`'

    # Property-table defaults, keyed by name for lookup.
    $propertyTableDefault = @{}
    foreach ($property in $propertyRows) {
        $propertyTableDefault[$property[0]] = $property[1]
    }

    # SetProperty custom actions (base type 51) drive the fresh-install default of checkbox toggles that
    # are absent from the Property table. Keep just their (property, literal-value) pairs for the lookup.
    $setPropertyActions = @(foreach ($action in $customActionRows) {
            $actionType = $action[2] -as [int]
            if ($null -ne $actionType -and ($actionType -band 0x3F) -eq 51) {
                , @($action[0], $action[1])
            }
        })

    # The set of command-line-settable-under-restriction properties.
    $secureProperties = @{}
    foreach ($secureName in ($propertyTableDefault['SecureCustomProperties'] -split ';' | Where-Object { $_ })) {
        $secureProperties[$secureName] = $true
    }

    # Map property -> UI label(s) for the best-effort description column.
    $descriptions = @{}
    foreach ($control in $checkBoxControlRows) {
        $property = $control[0]; $text = $control[1]
        if (-not $property) { continue }
        $label = ConvertTo-CleanLabel $text
        if ($label) { $descriptions[$property] = $label }
    }
    foreach ($radio in $radioRows) {
        $property = $radio[0]; $value = $radio[1]; $text = $radio[2]
        if (-not $property) { continue }
        $label = ConvertTo-CleanLabel $text
        if (-not $label) { continue }
        $option = "$value=$label"
        $descriptions[$property] = if ($descriptions.ContainsKey($property)) { "$($descriptions[$property]); $option" } else { $option }
    }

    $productName = $propertyTableDefault['ProductName']
    $productVersion = $propertyTableDefault['ProductVersion']

    # Non-public properties are hidden by default; these named ones stay visible when the package authors
    # them. Only properties the package actually authors are ever printed: a kept name the package omits
    # (whether public or private) is never in $parameterNames, so it is not shown.
    $keepNonPublic = @(
        'ProductName', 'ProductVersion', 'Manufacturer', 'TARGETDIR', 'WixUIRMOption',
        'WixShellExecTarget', 'ProductCode', 'UpgradeCode', 'WixUI_Mode'
    )
    # Descriptions the MSI itself does not carry for the kept properties. ProductName/ProductVersion/
    # Manufacturer are self-explanatory and intentionally left without one.
    $predefinedDescriptions = @{
        'ProductCode'        = 'GUID uniquely identifying this exact product and version; install, repair, and uninstall key off it.'
        'UpgradeCode'        = 'GUID identifying the product family; stays constant across versions so the installer can find and replace older ones.'
        'TARGETDIR'          = 'Root destination directory for the install; the base every other install path resolves against. Set by the installer at runtime.'
        'WixUI_Mode'         = 'Which WiX UI wizard set the package presents (for example Minimal, InstallDir, FeatureTree, or Mondo).'
        'WixShellExecTarget' = 'Target the WiX launch-on-exit action runs, typically the installed executable.'
        'WixUIRMOption'      = 'WiX UI Restart Manager setting: UseRM lets the installer close applications holding files in use; DisableRM turns that off.'
    }

    # A parameter is any Property-table row or CheckBox toggle - only what the package actually authors.
    # Kept names the package omits are not printed (nothing "not in package" is shown). Dedup and the
    # membership test below are case-sensitive (Select-Object -Unique and -ccontains) because MSI property
    # names are; a case-insensitive unique would fold FOO and foo.
    $checkBoxNames = @(foreach ($checkBox in $checkBoxRows) { $checkBox[0] })
    $parameterNames = @(@($propertyTableDefault.Keys) + $checkBoxNames | Select-Object -Unique)

    $rows = foreach ($parameterName in $parameterNames) {
        # Windows Installer's rule: a property is public when its name has no lowercase letters.
        $isPublic = $parameterName -cmatch '^[A-Z0-9_.]+$'
        $isKept = $keepNonPublic -contains $parameterName
        $inPropertyTable = $propertyTableDefault.ContainsKey($parameterName)
        $isCheckBox = $checkBoxNames -ccontains $parameterName

        # Public is always shown. A kept non-public is shown only when the package actually authors it: a
        # private property the package omits is not printed (it is never in $parameterNames to begin with).
        # -PublicOnly drops the kept non-publics too.
        $visible = $isPublic -or (-not $PublicOnly -and $isKept)
        if (-not $visible) {
            continue
        }

        $default = if ($inPropertyTable) { $propertyTableDefault[$parameterName] }
        elseif ($isCheckBox) { Get-CustomActionDefault $parameterName $setPropertyActions }
        else { '' }
        # Every $parameterName comes from the Property table or the CheckBox table, so one of these holds.
        $source = if ($inPropertyTable -and $isCheckBox) { 'Property+CheckBox' }
        elseif ($inPropertyTable) { 'Property' }
        else { 'CheckBox' }
        $description = if ($descriptions.ContainsKey($parameterName)) { $descriptions[$parameterName] }
        elseif ($predefinedDescriptions.ContainsKey($parameterName)) { $predefinedDescriptions[$parameterName] }
        else { '' }

        [pscustomobject]@{
            Name        = $parameterName
            Default     = $default
            Source      = $source
            Description = $description
            Secure      = [bool]$secureProperties[$parameterName]
            IsPublic    = $isPublic
        }
    }

    # Product identity leads (name, then version, then manufacturer); then settable toggles, then other
    # public, then the kept non-public; by name.
    $identityOrder = @{ 'ProductName' = 0; 'ProductVersion' = 1; 'Manufacturer' = 2 }
    $sortProperties = @(
        @{ Expression = { if ($identityOrder.ContainsKey($_.Name)) { $identityOrder[$_.Name] } else { 99 } } }
        @{ Expression = { $_.Source -like '*CheckBox*' }; Descending = $true }
        @{ Expression = 'IsPublic'; Descending = $true }
        'Name'
    )
    $ordered = $rows | Sort-Object $sortProperties

    # ---- Render -----------------------------------------------------------
    # A non-public property is flagged with a padlock in the leading Prv column. Caveat: 0x1F512 is a
    # surrogate pair (2 chars) that some viewers render as a single cell; as the first column it can then
    # shift the columns to its right on locked rows in those viewers. Spelled from its code point for
    # Windows PowerShell 5.1, which has no `u{...} escape.
    $lockChar = [System.Char]::ConvertFromUtf32(0x1F512)

    $display = foreach ($row in $ordered) {
        [pscustomobject]@{
            'Prv'           = if (-not $row.IsPublic) { $lockChar } else { '' }
            'Property Name' = $row.Name
            'Default Value' = $row.Default
            'Source'        = $row.Source
            'Description'   = $row.Description
            'Secure'        = $row.Secure
        }
    }

    $headerLines = @(
        "Package : $productName $productVersion"
        "Source  : $msiPath"
    )
    $legendLines = @(
        'How to read the Source and Default Value:'
        "  Property           Default Value is the exact value authored in the package's Property table."
        '  CheckBox           Default Value is derived from the package''s SetProperty custom actions by a'
        '                     static heuristic: the script scans those actions for a literal 0 or 1 assigned'
        '                     to the property and does not evaluate their run order or conditions, so it'
        '                     reflects the common fresh-install default and can differ for packages whose'
        '                     defaults are set by richer conditions.'
        '  Property+CheckBox  both of the above apply.'
        ''
        "  A $lockChar in the Prv column marks a non-public property (its name has a lowercase letter):"
        '  it cannot be set on the msiexec / winget command line.'
    )

    # Render once and reuse it for both console and report. Table mode uses explicit per-column widths, not
    # -AutoSize: -AutoSize sizes to the console and silently drops trailing columns (here Secure) when space
    # is tight, whereas fixed widths keep every column and make the console and file identical. Name and
    # Default size to their content (capped); Description is fixed and wraps.
    $rendered = if ($List) {
        $display | Format-List | Out-String
    }
    else {
        $nameWidth = [int][Math]::Min([Math]::Max((@($display.'Property Name') + 'Property Name' | Measure-Object -Property Length -Maximum).Maximum, 13), 50)
        $defaultWidth = [int][Math]::Min([Math]::Max((@($display.'Default Value') + 'Default Value' | Measure-Object -Property Length -Maximum).Maximum, 13), 45)
        $tableColumns = @(
            @{ Label = 'Prv'; Expression = { $_.'Prv' }; Width = 3 }
            @{ Label = 'Property Name'; Expression = { $_.'Property Name' }; Width = $nameWidth }
            @{ Label = 'Default Value'; Expression = { $_.'Default Value' }; Width = $defaultWidth }
            @{ Label = 'Source'; Expression = { $_.'Source' }; Width = 17 }
            @{ Label = 'Description'; Expression = { $_.'Description' }; Width = 60 }
            @{ Label = 'Secure'; Expression = { $_.'Secure' }; Width = 6 }
        )
        $display | Format-Table $tableColumns -Wrap | Out-String -Width 190
    }

    # Console: colour the header and legend, then the table (default) or list (-List).
    Write-Host ''
    foreach ($line in $headerLines) { Write-Host $line -ForegroundColor Green }
    Write-Host ''
    foreach ($line in $legendLines) { Write-Host $line -ForegroundColor DarkGray }
    Write-Host $rendered

    if ($PrintReport -or -not [string]::IsNullOrWhiteSpace($ReportOutputPath)) {
        $reportText = (($headerLines + '' + $legendLines + '') -join [Environment]::NewLine) + [Environment]::NewLine + $rendered
        $reportPath = Resolve-ReportPath -MsiPath $msiPath -MsiInTemporaryLocation $resolvedMsi.IsTemporaryLocation -ReportOutputPath $ReportOutputPath
        Set-Content -LiteralPath $reportPath -Value $reportText -Encoding UTF8
        Write-Host "Report saved: $reportPath" -ForegroundColor Green
    }
}
finally {
    if ($database) {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($database)
    }
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer)

    # Delete the throwaway download (a URL fetched this run, without -ReuseArtifacts). A -Name/-Path file
    # or a kept/reused download is never touched. The forced GC, needed only on this branch, releases the
    # MSI's file handle first so the file is not left locked.
    if ($resolvedMsi.DeleteAfterUse -and (Test-Path -LiteralPath $msiPath)) {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        try {
            Remove-Item -LiteralPath $msiPath -Force -ErrorAction Stop
            Write-Host "Deleted downloaded package: $msiPath" -ForegroundColor DarkYellow
        }
        catch {
            Write-Host "Could not delete downloaded package ${msiPath}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
