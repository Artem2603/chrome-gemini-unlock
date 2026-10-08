# End-to-end test of chrome-gemini-unlock.ps1 on Windows with a real Google Chrome, made for the
# windows-latest GitHub runner: Windows PowerShell 5.1, an elevated shell, Chrome installed for all
# users. It changes the Chrome profile, shortcuts and registry of the current Windows account, so
# outside CI it runs only with -AllowChanges. Exit code 0: every check passed.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\e2e.ps1 [-AllowChanges]
param([switch]$AllowChanges)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    Write-Host 'FAIL  tests\e2e.ps1 needs Windows PowerShell 5.1 (powershell.exe).'
    exit 1
}
if ($env:CI -ne 'true' -and -not $AllowChanges) {
    Write-Host 'This test changes the Chrome profile, shortcuts and registry of the current Windows account.'
    Write-Host 'It runs in CI (CI=true) or with -AllowChanges.'
    exit 1
}

. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $PSScriptRoot 'ChromeProbe.ps1')
# The script's message table (T), flag lists and Test-IsAdmin; T reads $Lang
$Agent = $false; $Country = 'us'; $Lang = 'en'
. (Import-ScriptDefinitions)

$Override       = '--variations-override-country=us --lang=en-US'
$WinPS          = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$UserDataDir    = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$LocalStatePath = Join-Path $UserDataDir 'Local State'
$PrefsPath      = Join-Path $UserDataDir 'Default\Preferences'
$BackupRoot     = Join-Path $env:LOCALAPPDATA 'chrome-gemini-unlock\backup'
$ManifestPath   = Join-Path $BackupRoot 'manifest.txt'
$ElevatedCopy   = Join-Path $BackupRoot 'elevated.ps1'
$ElevatedLog    = Join-Path $BackupRoot 'elevated.log'
$RunSubKey      = 'Software\Microsoft\Windows\CurrentVersion\Run'
$RunValueName   = 'GoogleChromeAutoLaunch_E2E'
$HandlerSubKey  = 'Software\Classes\ChromeHTML'
$CommandSubKey  = 'Software\Classes\ChromeHTML\shell\open\command'
$SeedFlags      = @('smooth-scrolling@2', 'glic@2')
$DesktopArgs    = '--profile-directory="Profile 1" --lang=ru'
$SharedArgs     = '--lang=de'
$TempRoot       = Join-Path ([System.IO.Path]::GetTempPath()) ('cgu-e2e-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$HKCU           = [Microsoft.Win32.Registry]::CurrentUser
$HKLM           = [Microsoft.Win32.Registry]::LocalMachine

Add-Type -AssemblyName System.Web.Extensions
$Serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$Serializer.MaxJsonLength = [int]::MaxValue
$Serializer.RecursionLimit = 1000
$Wsh = New-Object -ComObject WScript.Shell

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
$script:Passed = 0
$script:Failed = 0
$script:Step = ''
$script:FailedChecks = New-Object System.Collections.Generic.List[string]

function Write-Step([string]$Name) {
    $script:Step = $Name
    Write-Host ''
    Write-Host "== $Name" -ForegroundColor Cyan
}

function Write-Check([bool]$Ok, [string]$Text, [string]$Detail) {
    if ($Ok) { $script:Passed++; Write-Host "PASS  $Text" -ForegroundColor Green; return }
    $script:Failed++
    $script:FailedChecks.Add("$($script:Step): $Text")
    Write-Host "FAIL  $Text" -ForegroundColor Red
    if ($Detail) { Write-Host "      $Detail" }
}

function Format-Value($Value) {
    if ($null -eq $Value) { return '<missing>' }
    if ($Value -is [array]) { return '[' + (($Value | ForEach-Object { Format-Value $_ }) -join ', ') + ']' }
    return "'$Value'"
}

# Exact, case-sensitive comparison of a value or a list
function Test-Same([string]$Text, $Actual, $Expected) {
    $a = Format-Value $Actual
    $e = Format-Value $Expected
    Write-Check ($a -ceq $e) $Text "expected $e, got $a"
}

function Test-ExitCode($Result, [int]$Expected) {
    Write-Check ($Result.ExitCode -eq $Expected) "exit code $Expected" "got $($Result.ExitCode)"
}

function Test-Output($Result, [string]$Key) {
    $text = T $Key
    Write-Check ($Result.Output.Contains($text)) "output has the '$Key' message" "missing: $text"
}

# ---------------------------------------------------------------------------
# JSON, registry, shortcuts, processes
# ---------------------------------------------------------------------------
function Read-TestJson([string]$Path) {
    return $Serializer.DeserializeObject([System.IO.File]::ReadAllText($Path, $Utf8))
}

function Write-TestJson([string]$Path, $Data) {
    [System.IO.File]::WriteAllText($Path, $Serializer.Serialize($Data), $Utf8)
}

# The value at a key path, or $null when a key on the way is missing; a list comes back whole
function Get-JsonValue($Data, [string[]]$Keys) {
    $node = $Data
    foreach ($k in $Keys) {
        if (-not ($node -is [System.Collections.IDictionary]) -or -not $node.ContainsKey($k)) { return $null }
        $node = $node[$k]
    }
    return , $node
}

function Get-JsonSection($Data, [string]$Key) {
    # ::new() instead of New-Object: a PSObject-wrapped dictionary breaks Serialize()
    if (-not ($Data[$Key] -is [System.Collections.IDictionary])) { $Data[$Key] = [System.Collections.Generic.Dictionary[string,object]]::new() }
    return $Data[$Key]
}

function Get-Flags($State) {
    $list = Get-JsonValue $State 'browser', 'enabled_labs_experiments'
    if ($null -eq $list) { return , @() }
    return , @($list)
}

function Get-RegistryText([Microsoft.Win32.RegistryKey]$Hive, [string]$SubKey, [string]$Name) {
    $key = $Hive.OpenSubKey($SubKey)
    if (-not $key) { return $null }
    try { return $key.GetValue($Name) } finally { $key.Close() }
}

function Write-RegistryText([Microsoft.Win32.RegistryKey]$Hive, [string]$SubKey, [string]$Name, [string]$Value) {
    $key = $Hive.CreateSubKey($SubKey)
    try { $key.SetValue($Name, $Value) } finally { $key.Close() }
}

function Test-RegistryKey([Microsoft.Win32.RegistryKey]$Hive, [string]$SubKey) {
    $key = $Hive.OpenSubKey($SubKey)
    if (-not $key) { return $false }
    $key.Close()
    return $true
}

function New-TestShortcut([string]$Path, [string]$Arguments) {
    $link = $Wsh.CreateShortcut($Path)
    $link.TargetPath = $ChromeExe
    $link.Arguments = $Arguments
    $link.Save()
}

function Get-ShortcutArguments([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return [string]$Wsh.CreateShortcut($Path).Arguments
}

function Get-ManifestLines {
    if (-not (Test-Path -LiteralPath $ManifestPath)) { return , @() }
    return , [System.IO.File]::ReadAllLines($ManifestPath)
}

# The backup file the manifest names for Target; $null unless exactly one "name  ->  Target" line matches
function Get-ManifestBackup([string]$Target, [string]$NamePattern) {
    $names = @(foreach ($line in (Get-ManifestLines)) {
        $i = $line.IndexOf('  ->  ')
        if ($i -gt 0 -and $line.Substring($i + 6) -eq $Target -and $line.Substring(0, $i) -like $NamePattern) { $line.Substring(0, $i) }
    })
    if ($names.Count -ne 1) { return $null }
    return Join-Path $BackupRoot $names[0]
}

function Test-ManifestBackup([string]$Text, [string]$Target, [string]$NamePattern) {
    $backup = Get-ManifestBackup $Target $NamePattern
    Write-Check ($backup -and (Test-Path -LiteralPath $backup)) "manifest line and backup file: $Text" "no single '$NamePattern  ->  $Target' line with an existing backup"
    return $backup
}

function Find-TestChrome {
    $paths = @()
    foreach ($dir in $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) {
        if ($dir) { $paths += Join-Path $dir $ChromeSub }
    }
    $appPath = Get-RegistryText $HKLM 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' ''
    if ($appPath) { $paths += $appPath.Trim('"') }
    foreach ($p in $paths) { if (Test-Path -LiteralPath $p -PathType Leaf) { return $p } }
    return $null
}

function Get-ChromeIds { return , @(Get-Process chrome -ErrorAction SilentlyContinue | ForEach-Object { $_.Id }) }

function Wait-ChromeGone([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-ChromeIds).Count -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
    return (Get-ChromeIds).Count -eq 0
}

function Stop-AllChrome {
    Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if (-not (Wait-ChromeGone 30)) { Write-Host 'chrome.exe is still running after Stop-Process' }
}

function Start-TestChrome([string[]]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo $ChromeExe
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    # Both pipes are drained in the background, so Chrome never blocks on a full one
    $null = $proc.StandardOutput.ReadToEndAsync()
    $null = $proc.StandardError.ReadToEndAsync()
    return $proc
}

# Runs a program and returns its exit code and everything it printed. The lines are joined by
# hand: Out-String may wrap long lines at the console width.
function Invoke-Captured([string]$Exe, [string[]]$Arguments, [string]$Label) {
    # A line on stderr must not stop this test; it is collected with the rest of the output
    $ErrorActionPreference = 'Continue'
    Write-Host "> $Label" -ForegroundColor DarkGray
    # Empty, closed stdin: a prompt that slips through reads nothing instead of waiting forever
    $lines = @(@() | & $Exe @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $code = $LASTEXITCODE
    foreach ($line in $lines) { Write-Host "  | $line" -ForegroundColor DarkGray }
    return [pscustomobject]@{ ExitCode = $code; Output = ($lines -join "`n") }
}

# The script in a separate PowerShell; -NonInteractive makes a prompt fail instead of hanging
function Invoke-Unlock([string[]]$Arguments, [string]$Shell = $WinPS) {
    $all = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ScriptUnderTest) + $Arguments
    return Invoke-Captured $Shell $all "$(Split-Path -Leaf $Shell) $($Arguments -join ' ')"
}

# What the elevated PowerShell runs after the UAC prompt (Invoke-ElevatedShortcuts), started
# directly: this shell is elevated already, so no prompt appears
function Invoke-Bootstrap([string]$Arguments, [string]$Hash) {
    $bootstrap = New-ElevatedBootstrap $ElevatedCopy $Hash $Arguments
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($bootstrap))
    if (Test-Path -LiteralPath $ElevatedLog) { Remove-Item -LiteralPath $ElevatedLog -Force }
    $all = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
    return Invoke-Captured $WinPS $all "powershell.exe -EncodedCommand <bootstrap $Arguments>"
}

function Get-ElevatedLog {
    if (-not (Test-Path -LiteralPath $ElevatedLog)) { return '' }
    return [System.IO.File]::ReadAllText($ElevatedLog)
}

# ---------------------------------------------------------------------------
# Test
# ---------------------------------------------------------------------------
$ChromeExe = $null
$Pwsh = $null
$DesktopLnk = $null
$SharedLnk = $null
$CreatedMachineHandler = $false

try {
    Write-Step 'Prepare'
    Write-Host "Windows PowerShell $($PSVersionTable.PSVersion), UI culture $((Get-UICulture).Name), session $((Get-Process -Id $PID).SessionId)"
    if (-not (Test-IsAdmin)) { throw 'This test needs an elevated shell (the windows-latest runner provides one).' }
    $ChromeExe = Find-TestChrome
    if (-not $ChromeExe) { throw "Google Chrome not found (looked for $ChromeSub in Program Files and LOCALAPPDATA)." }
    Write-Host "Chrome: $ChromeExe, version $((Get-Item -LiteralPath $ChromeExe).VersionInfo.ProductVersion)"
    if ((Get-UICulture).TwoLetterISOLanguageName -ne 'en') { Write-Host 'The UI language is not English: the script prints other messages than the ones checked here.' }
    $Pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Pwsh) { Write-Host "PowerShell 7: $($Pwsh.Path)" } else { Write-Host 'PowerShell 7: not installed, its steps are skipped' }

    Stop-AllChrome
    # Chrome creates Local State and the Default profile on its first start
    $first = Start-TestChrome @('--headless=new', '--no-first-run', "--user-data-dir=$UserDataDir", '--dump-dom', 'about:blank')
    if (-not $first.WaitForExit(120000)) { Write-Host 'Chrome --dump-dom did not exit within 120 s' }
    Stop-AllChrome
    if (-not (Test-Path -LiteralPath $LocalStatePath)) { throw "Chrome did not create $LocalStatePath" }
    if (-not (Test-Path -LiteralPath $PrefsPath)) {
        Write-Host "Chrome did not create $PrefsPath, writing a minimal one"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PrefsPath) | Out-Null
        [System.IO.File]::WriteAllText($PrefsPath, '{}', $Utf8)
    }
    if (Test-Path -LiteralPath $BackupRoot) { Remove-Item -LiteralPath $BackupRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

    # Seed: a foreign flag, a managed flag in another state, Russian languages
    $state = Read-TestJson $LocalStatePath
    (Get-JsonSection $state 'browser')['enabled_labs_experiments'] = [object[]]$SeedFlags
    (Get-JsonSection $state 'intl')['app_locale'] = 'ru'
    $null = $state.Remove('variations_permanent_overridden_country')
    Write-TestJson $LocalStatePath $state
    $prefs = Read-TestJson $PrefsPath
    $intl = Get-JsonSection $prefs 'intl'
    $intl['accept_languages'] = 'ru,en'
    $intl['selected_languages'] = 'ru,en'
    $SeedPrefsLocale = Get-JsonValue $prefs 'intl', 'app_locale'
    Write-TestJson $PrefsPath $prefs

    $desktopDir = [Environment]::GetFolderPath('Desktop')
    if (-not $desktopDir) { $desktopDir = Join-Path $env:USERPROFILE 'Desktop' }
    New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null
    $DesktopLnk = Join-Path $desktopDir 'E2E Chrome.lnk'
    $SharedLnk = Join-Path ([Environment]::GetFolderPath('CommonStartMenu')) 'E2E Chrome Shared.lnk'
    New-TestShortcut $DesktopLnk $DesktopArgs
    New-TestShortcut $SharedLnk $SharedArgs
    Test-Same 'desktop shortcut seeded' (Get-ShortcutArguments $DesktopLnk) $DesktopArgs
    Test-Same 'shared shortcut seeded' (Get-ShortcutArguments $SharedLnk) $SharedArgs

    $RunOriginal = '"' + $ChromeExe + '" --no-startup-window /prefetch:5'
    Write-RegistryText $HKCU $RunSubKey $RunValueName $RunOriginal

    if (Test-RegistryKey $HKCU $HandlerSubKey) { $HKCU.DeleteSubKeyTree($HandlerSubKey, $false) }
    $machineCommand = Get-RegistryText $HKLM $CommandSubKey ''
    if (-not $machineCommand) {
        $CreatedMachineHandler = -not (Test-RegistryKey $HKLM $HandlerSubKey)
        $machineCommand = '"' + $ChromeExe + '" --single-argument %1'
        Write-RegistryText $HKLM $CommandSubKey '' $machineCommand
        Write-Host "Created HKLM\$CommandSubKey"
    }
    Write-Host "HKLM\$CommandSubKey = $machineCommand"
    $HandlerExpected = $null
    if ($machineCommand -match '^("[^"]+")\s*(.*)$') { $HandlerExpected = ("$($Matches[1]) $Override $($Matches[2])").TrimEnd() }

    # -----------------------------------------------------------------------
    Write-Step 'Run 1: -Force -NoLaunch'
    $r = Invoke-Unlock -Arguments @('-Force', '-NoLaunch')
    Test-ExitCode $r 0
    Test-Output $r 'noLaunch'
    $state = Read-TestJson $LocalStatePath
    Test-Same 'Local State flags: foreign flag kept, glic@2 replaced by the base flags' (Get-Flags $state) (@('smooth-scrolling@2') + $BaseFlags)
    Test-Same 'Local State intl.app_locale' (Get-JsonValue $state 'intl', 'app_locale') 'en-US'
    Test-Same 'Local State variations_permanent_overridden_country' (Get-JsonValue $state 'variations_permanent_overridden_country') 'us'
    $prefs = Read-TestJson $PrefsPath
    Test-Same 'Preferences intl.app_locale' (Get-JsonValue $prefs 'intl', 'app_locale') 'en-US'
    Test-Same 'Preferences intl.accept_languages' (Get-JsonValue $prefs 'intl', 'accept_languages') 'en-US,en'
    Test-Same 'Preferences intl.selected_languages' (Get-JsonValue $prefs 'intl', 'selected_languages') 'en-US,en'
    Test-Same 'desktop shortcut arguments' (Get-ShortcutArguments $DesktopLnk) "$Override --profile-directory=`"Profile 1`""
    Test-Same 'shared shortcut arguments' (Get-ShortcutArguments $SharedLnk) $Override
    Test-Same 'autostart value' (Get-RegistryText $HKCU $RunSubKey $RunValueName) ('"' + $ChromeExe + '" ' + $Override + ' --no-startup-window /prefetch:5')
    $handler = Get-RegistryText $HKCU $CommandSubKey ''
    if ($HandlerExpected) { Test-Same 'HKCU link handler command' $handler $HandlerExpected }
    else { Write-Check ([string]$handler -like "*$Override*--single-argument*") 'HKCU link handler command has the override before --single-argument' "got $(Format-Value $handler)" }

    $backup = Test-ManifestBackup 'Local State' $LocalStatePath 'Local State'
    if ($backup) { Test-Same 'backup of Local State has the seeded flags' (Get-Flags (Read-TestJson $backup)) $SeedFlags }
    $backup = Test-ManifestBackup 'Default profile' $PrefsPath 'profiles\Default\Preferences'
    if ($backup) { Test-Same 'backup of Preferences has the seeded languages' (Get-JsonValue (Read-TestJson $backup) 'intl', 'accept_languages') 'ru,en' }
    $backup = Test-ManifestBackup 'desktop shortcut' $DesktopLnk 'shortcuts\*\E2E Chrome.lnk'
    if ($backup) { Test-Same 'backup of the desktop shortcut has the seeded arguments' (Get-ShortcutArguments $backup) $DesktopArgs }
    $backup = Test-ManifestBackup 'shared shortcut' $SharedLnk 'shortcuts\*\E2E Chrome Shared.lnk'
    if ($backup) { Test-Same 'backup of the shared shortcut has the seeded arguments' (Get-ShortcutArguments $backup) $SharedArgs }
    $lines = Get-ManifestLines
    $runLine = "[registry] HKCU\$RunSubKey  $RunValueName = $RunOriginal"
    Write-Check ($lines -ccontains $runLine) 'manifest line: autostart value' "missing: $runLine"
    $createdLine = @($lines | Where-Object { $_.StartsWith('[registry] created HKCU\Software\Classes\ChromeHTML ') })
    Write-Check ($createdLine.Count -eq 1) 'manifest line: created HKCU\Software\Classes\ChromeHTML' "found $($createdLine.Count) such lines"
    $Run1Manifest = [System.IO.File]::ReadAllText($ManifestPath)
    $Run1Desktop = Get-ShortcutArguments $DesktopLnk
    $Run1Shared = Get-ShortcutArguments $SharedLnk

    # -----------------------------------------------------------------------
    Write-Step 'Run 2: the same again changes nothing'
    $r = Invoke-Unlock -Arguments @('-Force', '-NoLaunch')
    Test-ExitCode $r 0
    Test-Same 'desktop shortcut arguments unchanged' (Get-ShortcutArguments $DesktopLnk) $Run1Desktop
    Test-Same 'shared shortcut arguments unchanged' (Get-ShortcutArguments $SharedLnk) $Run1Shared
    Write-Check ([System.IO.File]::ReadAllText($ManifestPath) -ceq $Run1Manifest) 'manifest.txt unchanged'

    # -----------------------------------------------------------------------
    Write-Step 'Run 3: -Agent adds the agent flags'
    $r = Invoke-Unlock -Arguments @('-Agent', '-Force', '-NoLaunch')
    Test-ExitCode $r 0
    Test-Output $r 'agentOn'
    $flags = Get-Flags (Read-TestJson $LocalStatePath)
    Test-Same 'Local State flags with -Agent' $flags (@('smooth-scrolling@2') + $BaseFlags + $AgentFlags)
    Write-Check ($flags.Count -eq 12) 'foreign flag + 11 managed flags' "got $($flags.Count) entries"

    # -----------------------------------------------------------------------
    Write-Step 'Run 4: without -Agent the agent flags go away'
    $r = Invoke-Unlock -Arguments @('-Force', '-NoLaunch')
    Test-ExitCode $r 0
    $flags = Get-Flags (Read-TestJson $LocalStatePath)
    Test-Same 'Local State flags without -Agent' $flags (@('smooth-scrolling@2') + $BaseFlags)
    Write-Check ($flags.Count -eq 6) 'foreign flag + 5 base flags' "got $($flags.Count) entries"

    # -----------------------------------------------------------------------
    Write-Step 'Chrome reads the Local State the script wrote'
    # Chrome refuses DevTools on its default user data folder, so the probe runs on a copy of it
    $probeDir = Join-Path $TempRoot 'probe'
    New-Item -ItemType Directory -Force -Path (Join-Path $probeDir 'Default') | Out-Null
    Copy-Item -LiteralPath $LocalStatePath -Destination (Join-Path $probeDir 'Local State')
    Copy-Item -LiteralPath $PrefsPath -Destination (Join-Path $probeDir 'Default\Preferences')
    try {
        $launch = Get-ChromeLaunchState -ChromePath $ChromeExe -UserDataDir $probeDir -Arguments ($Override -split ' ')
        Write-Host "$($launch.Product): $($launch.FlagSwitches -join ' ')"
        Write-Check ($launch.EnabledFeatures -ccontains 'Glic') 'Chrome enables the Glic feature' "enabled features: $($launch.EnabledFeatures -join ', ')"
        Write-Check ($launch.Arguments -ccontains '--variations-override-country=us') 'Chrome runs with --variations-override-country=us'
        Write-Check ([string]$launch.Language -like 'en-US*') 'pages see en-US' "navigator.language is '$($launch.Language)'"
    } catch { Write-Check $false 'Chrome probe' $_.Exception.Message }
    Write-Check (Wait-ChromeGone 30) 'no chrome.exe left after the probe'
    Stop-AllChrome

    # -----------------------------------------------------------------------
    Write-Step 'Confirmation: no -Force in a non-interactive session while Chrome runs'
    $guardDir = Join-Path $TempRoot 'guard'
    New-Item -ItemType Directory -Force -Path $guardDir | Out-Null
    $guard = Start-TestChrome @('--headless=new', '--no-first-run', '--remote-debugging-port=0', "--user-data-dir=$guardDir", 'about:blank')
    $portFile = Join-Path $guardDir 'DevToolsActivePort'
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path -LiteralPath $portFile) -and -not $guard.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    Write-Check ((Test-Path -LiteralPath $portFile) -and -not $guard.HasExited) 'a headless chrome.exe runs in this session'
    $before = [System.IO.File]::ReadAllBytes($LocalStatePath)
    $r = Invoke-Unlock -Arguments @('-NoLaunch')
    Test-ExitCode $r 1
    Test-Output $r 'needForce'
    Write-Check ([Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($LocalStatePath))) 'Local State unchanged'
    Write-Check (-not $guard.HasExited) 'Chrome was not closed'
    if ($Pwsh) {
        # The same from a non-interactive PowerShell 7, which hands the run over to Windows PowerShell
        $r = Invoke-Unlock -Arguments @('-NoLaunch') -Shell $Pwsh.Path
        Test-ExitCode $r 1
        Test-Output $r 'needForce'
        Write-Check ([Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($LocalStatePath))) 'Local State unchanged (PowerShell 7)'
        Write-Check (-not $guard.HasExited) 'Chrome was not closed (PowerShell 7)'
    }
    Stop-AllChrome

    # -----------------------------------------------------------------------
    Write-Step 'Restore: -Restore -Force -NoLaunch'
    $r = Invoke-Unlock -Arguments @('-Restore', '-Force', '-NoLaunch')
    Test-ExitCode $r 0
    Test-Output $r 'restoreDone'
    $state = Read-TestJson $LocalStatePath
    Test-Same 'Local State flags back to the seeded ones' (Get-Flags $state) $SeedFlags
    Test-Same 'Local State intl.app_locale back' (Get-JsonValue $state 'intl', 'app_locale') 'ru'
    Write-Check (-not $state.ContainsKey('variations_permanent_overridden_country')) 'Local State variations_permanent_overridden_country removed'
    $prefs = Read-TestJson $PrefsPath
    Test-Same 'Preferences intl.app_locale back' (Get-JsonValue $prefs 'intl', 'app_locale') $SeedPrefsLocale
    Test-Same 'Preferences intl.accept_languages back' (Get-JsonValue $prefs 'intl', 'accept_languages') 'ru,en'
    Test-Same 'Preferences intl.selected_languages back' (Get-JsonValue $prefs 'intl', 'selected_languages') 'ru,en'
    Test-Same 'desktop shortcut arguments back' (Get-ShortcutArguments $DesktopLnk) $DesktopArgs
    Test-Same 'shared shortcut arguments back' (Get-ShortcutArguments $SharedLnk) $SharedArgs
    Test-Same 'autostart value back' (Get-RegistryText $HKCU $RunSubKey $RunValueName) $RunOriginal
    Write-Check (-not (Test-RegistryKey $HKCU $HandlerSubKey)) 'HKCU\Software\Classes\ChromeHTML removed'
    foreach ($line in (Get-ManifestLines)) {
        if ($line -match '^\[registry\] created HKCU\\(\S+) ') {
            Write-Check (-not (Test-RegistryKey $HKCU $Matches[1])) "HKCU\$($Matches[1]) removed"
        }
    }

    # -----------------------------------------------------------------------
    Write-Step 'PowerShell 7 hands the run over to Windows PowerShell'
    if (-not $Pwsh) {
        Write-Host 'SKIP  pwsh.exe not found'
    } else {
        $r = Invoke-Unlock -Arguments @('-Force', '-NoLaunch') -Shell $Pwsh.Path
        Test-ExitCode $r 0
        Test-Output $r 'relaunch'
        Test-Output $r 'noLaunch'
        Test-Same 'Local State flags after the PowerShell 7 run' (Get-Flags (Read-TestJson $LocalStatePath)) (@('smooth-scrolling@2') + $BaseFlags)
        $r = Invoke-Unlock -Arguments @('-Restore', '-Force', '-NoLaunch')
        Test-ExitCode $r 0
        Test-Same 'Local State flags restored again' (Get-Flags (Read-TestJson $LocalStatePath)) $SeedFlags
        Test-Same 'desktop shortcut arguments restored again' (Get-ShortcutArguments $DesktopLnk) $DesktopArgs
    }

    # -----------------------------------------------------------------------
    Write-Step 'Elevated copy: checked by its hash, then it handles the shared shortcuts'
    # The bytes Invoke-ElevatedShortcuts writes: the script text as UTF-8 without a BOM
    $copyBytes = $Utf8.GetBytes([System.IO.File]::ReadAllText($ScriptUnderTest))
    $copyHash = Get-Sha256Hex $copyBytes
    $bootArgs = "-SystemShortcutsOnly -Country us -BackupDir $(ConvertTo-PSLiteral $BackupRoot) -LogFile $(ConvertTo-PSLiteral $ElevatedLog)"
    [System.IO.File]::WriteAllBytes($ElevatedCopy, [byte[]]($copyBytes + [byte]10))
    $r = Invoke-Bootstrap $bootArgs $copyHash
    Test-ExitCode $r 3
    Test-Same 'a changed copy leaves the shared shortcut alone' (Get-ShortcutArguments $SharedLnk) $SharedArgs
    [System.IO.File]::WriteAllBytes($ElevatedCopy, $copyBytes)
    $r = Invoke-Bootstrap $bootArgs $copyHash
    Test-ExitCode $r 0
    Test-Same 'shared shortcut arguments set by the elevated copy' (Get-ShortcutArguments $SharedLnk) $Override
    Test-Same 'desktop shortcut left to the main run' (Get-ShortcutArguments $DesktopLnk) $DesktopArgs
    Write-Check ((Get-ElevatedLog).Contains((T 'shortcut' $SharedLnk))) 'elevated.log reports the shared shortcut' "log: $(Get-ElevatedLog)"
    $r = Invoke-Bootstrap "$bootArgs -Restore" $copyHash
    Test-ExitCode $r 0
    Test-Same 'shared shortcut arguments restored by the elevated copy' (Get-ShortcutArguments $SharedLnk) $SharedArgs
    Write-Check ((Get-ElevatedLog).Contains((T 'restoreShortcut' $SharedLnk))) 'elevated.log reports the restored shortcut' "log: $(Get-ElevatedLog)"
    Remove-Item -LiteralPath $ElevatedCopy -Force -ErrorAction SilentlyContinue

    # -----------------------------------------------------------------------
    Write-Step 'Elevated: Chrome is not started from an elevated script'
    $chromeBefore = Get-ChromeIds
    $r = Invoke-Unlock -Arguments @('-Force')
    Test-ExitCode $r 0
    Test-Output $r 'noLaunchAdmin'
    Start-Sleep -Seconds 3
    $chromeAfter = Get-ChromeIds
    $started = @($chromeAfter | Where-Object { $chromeBefore -notcontains $_ })
    Write-Check ($started.Count -eq 0) 'no chrome.exe was started' "new chrome.exe processes: $($started -join ', ')"
} catch {
    Write-Check $false "test aborted: $($_.Exception.Message)" $_.InvocationInfo.PositionMessage
} finally {
    Write-Step 'Cleanup'
    try {
        Stop-AllChrome
        foreach ($lnk in $DesktopLnk, $SharedLnk) {
            if ($lnk -and (Test-Path -LiteralPath $lnk)) { Remove-Item -LiteralPath $lnk -Force }
        }
        $key = $HKCU.OpenSubKey($RunSubKey, $true)
        if ($key) { try { $key.DeleteValue($RunValueName, $false) } finally { $key.Close() } }
        if ($CreatedMachineHandler) { $HKLM.DeleteSubKeyTree($HandlerSubKey, $false) }
        if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Host 'Test shortcuts and the test autostart value removed'
    } catch { Write-Host "Cleanup: $($_.Exception.Message)" }
}

Write-Host ''
foreach ($f in $script:FailedChecks) { Write-Host "FAIL  $f" -ForegroundColor Red }
Write-Host "e2e: $script:Passed passed, $script:Failed failed"
if ($script:Failed -or $script:Passed -eq 0) { exit 1 }
exit 0
