# Checks the Glic flags of chrome-gemini-unlock.ps1 against a real Google Chrome: for each managed
# flag, a Local State made by the script's own Set-LocalStateSettings has to make Chrome enable at
# least one feature, while Chrome runs with the script's override switches and pages see en-US.
# Runs in Windows PowerShell 5.1 and PowerShell 7 (Windows, Linux). Exit code 0: all checks passed.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\chrome-flags.ps1 [-ChromePath <chrome>] [-Country us]
param(
    [string]$ChromePath,
    [ValidatePattern('^[A-Za-z]{2}\z')]
    [string]$Country = 'us'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $PSScriptRoot 'ChromeProbe.ps1')

$Country = $Country.ToLowerInvariant()
$Agent = $false
$Lang = 'en'
. (Import-ScriptDefinitions)

$onWindows = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows
if (-not $ChromePath) {
    if ($onWindows) {
        foreach ($dir in $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) {
            if ($dir -and (Test-Path -LiteralPath (Join-Path $dir $ChromeSub))) { $ChromePath = Join-Path $dir $ChromeSub; break }
        }
    } else {
        $command = Get-Command google-chrome -ErrorAction SilentlyContinue
        if ($command) { $ChromePath = $command.Source }
    }
}
if (-not $ChromePath -or -not (Test-Path -LiteralPath $ChromePath)) {
    Write-Host 'Google Chrome not found. Pass its path with -ChromePath.'
    exit 1
}
# Chrome on Linux ignores --lang and takes its language from the environment. On Windows, where
# the script runs, --lang and Local State decide, and that is what the language check covers there.
if (-not $onWindows) { $env:LANGUAGE = 'en_US'; $env:LC_ALL = 'en_US.UTF-8' }

$OverrideSwitches = @($OverrideArgs -split ' ')
$AllFlags = @($BaseFlags + $AgentFlags)
$BogusFlag = 'glic-chrome-gemini-unlock-bogus@1'
$WorkRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('chrome-flags-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$script:RunCount = 0
$script:Passed = 0
$script:Failed = 0

function Write-Result([bool]$Ok, [string]$Text) {
    if ($Ok) { $script:Passed++; Write-Host "PASS  $Text" } else { $script:Failed++; Write-Host "FAIL  $Text" }
}

# Chrome's helper processes can keep files open for a moment after the browser has exited
function Remove-WorkDir([string]$Path) {
    for ($i = 1; (Test-Path -LiteralPath $Path); $i++) {
        try { Remove-Item -LiteralPath $Path -Recurse -Force }
        catch {
            if ($i -ge 20) { Write-Host "Could not remove ${Path}: $($_.Exception.Message)"; return }
            Start-Sleep -Milliseconds 500
        }
    }
}

# Reads Chrome's JSON like the script does: ConvertFrom-Json of Windows PowerShell 5.1 fails on
# keys that differ only in case
function Read-ChromeJson([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path)
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        Add-Type -AssemblyName System.Web.Extensions
        $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $serializer.MaxJsonLength = [int]::MaxValue
        return $serializer.DeserializeObject($text)
    }
    return ConvertFrom-Json -InputObject $text
}

# Starts Chrome once on a fresh user data folder whose Local State the script itself produced
function Invoke-FlagRun([string[]]$FlagSet) {
    $script:RunCount++
    $dir = Join-Path $WorkRoot ('run' + $script:RunCount)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $state = [System.Collections.Generic.Dictionary[string,object]]::new()
    # Set-LocalStateSettings reads $Flags from the caller
    $Flags = $FlagSet
    Set-LocalStateSettings $state
    [System.IO.File]::WriteAllText((Join-Path $dir 'Local State'), (ConvertTo-Json -InputObject $state -Depth 20 -Compress), $Utf8)
    $launch = Get-ChromeLaunchState -ChromePath $ChromePath -UserDataDir $dir -Arguments $OverrideSwitches
    return [pscustomobject]@{ Dir = $dir; Launch = $launch }
}

# What keeps a launch from counting as working: no feature, a missing override switch, another language
function Get-LaunchProblems($Launch, [bool]$ExpectFeatures = $true) {
    $problems = @()
    if ($ExpectFeatures -and $Launch.EnabledFeatures.Count -eq 0) { $problems += 'no feature enabled' }
    foreach ($s in $OverrideSwitches) {
        if ($Launch.Arguments -cnotcontains $s) { $problems += "command line lacks $s" }
    }
    if (-not $Launch.Language.StartsWith('en-US', [StringComparison]::Ordinal)) { $problems += "navigator.language is '$($Launch.Language)'" }
    return $problems
}

$chromeMajor = 0
$perFlagFeatures = New-Object System.Collections.Generic.List[string]
# Flags the script's own expiry table says this Chrome ignores; Chrome has to agree
$expiredFlags = New-Object System.Collections.Generic.List[string]
try {
    New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
    Write-Host "Chrome:   $ChromePath"
    Write-Host "Switches: $OverrideArgs"
    Write-Host ''

    # ---- Each managed flag on its own
    foreach ($flag in $AllFlags) {
        $name = $flag.Split('@')[0]
        try {
            $run = Invoke-FlagRun @($flag)
            Remove-WorkDir $run.Dir
            if (-not $chromeMajor -and $run.Launch.Product -match '/(\d+)\.') { $chromeMajor = [int]$Matches[1] }
            foreach ($f in $run.Launch.EnabledFeatures) { if (-not $perFlagFeatures.Contains($f)) { $perFlagFeatures.Add($f) } }
            # Chrome skips a flag it does not know or whose expiry milestone has passed
            $expiry = Get-FlagExpiry $name $chromeMajor
            $expired = $expiry -lt $chromeMajor
            if ($expired) { $expiredFlags.Add($flag) }
            $problems = @(Get-LaunchProblems $run.Launch (-not $expired))
            if ($expired -and $run.Launch.EnabledFeatures.Count) {
                $problems += "Chrome $chromeMajor applies it, the script's table says it expired after Chrome $expiry"
            } elseif (-not $expired -and $run.Launch.EnabledFeatures.Count -eq 0) {
                $problems += "Chrome $chromeMajor ignores it, the script's table says it works until Chrome $expiry"
            }
            $features = $run.Launch.EnabledFeatures -join ', '
            if (-not $features) { $features = '(none)' }
            if ($expired) { $features += " (expired after Chrome $expiry, as the script's table says)" }
            $text = "$flag -> $features"
            if ($problems) { $text += '  [' + ($problems -join '; ') + ']' }
            Write-Result ($problems.Count -eq 0) $text
        } catch { Write-Result $false "$flag -> $($_.Exception.Message)" }
    }

    # ---- Negative control: an entry Chrome does not know must not produce any flag switch
    try {
        $run = Invoke-FlagRun @($BogusFlag)
        Remove-WorkDir $run.Dir
        $switches = $run.Launch.FlagSwitches
        $text = "negative control $BogusFlag -> no flag switches"
        if ($switches.Count) { $text = "negative control $BogusFlag -> unexpected flag switches: $($switches -join ' ')" }
        Write-Result ($switches.Count -eq 0) $text
    } catch { Write-Result $false "negative control $BogusFlag -> $($_.Exception.Message)" }

    # ---- All managed flags together, as a run with -Agent writes them
    try {
        $run = Invoke-FlagRun $AllFlags
        $problems = @(Get-LaunchProblems $run.Launch)
        # A flag that turns off what another one turns on would show up here
        $missing = @($perFlagFeatures | Where-Object { $run.Launch.EnabledFeatures -cnotcontains $_ })
        if ($missing) { $problems += 'features missing compared to the single runs: ' + ($missing -join ', ') }
        $text = "all $($AllFlags.Count) flags -> $($run.Launch.EnabledFeatures -join ', ')"
        if ($problems) { $text += '  [' + ($problems -join '; ') + ']' }
        Write-Result ($problems.Count -eq 0) $text

        # Chrome rewrites Local State on exit and drops entries it does not know or that expired:
        # exactly the expired ones may go
        $saved = Read-ChromeJson (Join-Path $run.Dir 'Local State')
        $entries = @()
        if ($saved.browser) { $entries = @($saved.browser.enabled_labs_experiments) }
        $lost = @($AllFlags | Where-Object { $entries -cnotcontains $_ })
        $country = [string]$saved.variations_permanent_overridden_country
        $problems = @()
        $unexpected = @($lost | Where-Object { -not $expiredFlags.Contains($_) })
        $kept = @($expiredFlags | Where-Object { $lost -cnotcontains $_ })
        if ($unexpected) { $problems += 'flags dropped by Chrome: ' + ($unexpected -join ', ') }
        if ($kept) { $problems += 'expired flags Chrome kept: ' + ($kept -join ', ') }
        if ($country -cne $Country) { $problems += "variations_permanent_overridden_country is '$country'" }
        $text = "Local State after exit: $($AllFlags.Count - $lost.Count) of $($AllFlags.Count) flags kept, country '$country'"
        if ($problems) { $text += '  [' + ($problems -join '; ') + ']' }
        Write-Result ($problems.Count -eq 0) $text
        Remove-WorkDir $run.Dir
    } catch { Write-Result $false "all $($AllFlags.Count) flags -> $($_.Exception.Message)" }
} finally {
    Remove-WorkDir $WorkRoot
}

Write-Host ''
Write-Host "Chrome $chromeMajor, $($AllFlags.Count) managed flags: $script:Passed passed, $script:Failed failed"
if ($script:Failed) { exit 1 }
exit 0
