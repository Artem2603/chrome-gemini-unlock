# Starts a headless Google Chrome on a given user data folder and asks it over the DevTools
# protocol what it really runs with: its command line, including the switches Chrome builds from
# the chrome://flags entries in Local State, and the language a web page sees.
# Works in Windows PowerShell 5.1 and PowerShell 7 (Windows, Linux).
#
#   . (Join-Path $PSScriptRoot 'ChromeProbe.ps1')
#   $state = Get-ChromeLaunchState -ChromePath $exe -UserDataDir $dir -Arguments '--lang=en-US'

# Quotes one argument so that Windows (CommandLineToArgvW) and .NET on Linux read it back unchanged
function ConvertTo-ProbeArgument([string]$Arg) {
    if ($Arg -and $Arg -notmatch '[\s"]') { return $Arg }
    # Backslashes are literal unless they precede a quote: there they are doubled and the quote escaped
    $escaped = [regex]::Replace($Arg, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
    $escaped = [regex]::Replace($escaped, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
    return '"' + $escaped + '"'
}

# The last lines Chrome wrote to stderr, for error messages; empty while helper processes still hold the pipe
function Get-ProbeOutput($Task) {
    try {
        if (-not $Task.Wait(2000)) { return '' }
        $lines = @($Task.Result -split "`r?`n" | Where-Object { $_.Trim() })
        if ($lines.Count -eq 0) { return '' }
        return " Chrome stderr: " + (($lines | Select-Object -Last 5) -join ' | ')
    } catch { return '' }
}

function Stop-ProbeProcess($Process) {
    if ($Process.HasExited) { return }
    # Kill($true) also ends the helper processes in .NET Core; .NET Framework only has Kill()
    try { $Process.Kill($true) } catch { try { $Process.Kill() } catch { } }
    $null = $Process.WaitForExit(10000)
}

function Receive-CdpText($Cdp) {
    $stream = New-Object System.IO.MemoryStream
    # A message can arrive in several frames
    do {
        $segment = [System.ArraySegment[byte]]::new($Cdp.Buffer)
        $result = $Cdp.Socket.ReceiveAsync($segment, $Cdp.Token).GetAwaiter().GetResult()
        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            throw 'Chrome closed the DevTools connection'
        }
        $stream.Write($Cdp.Buffer, 0, $result.Count)
    } while (-not $result.EndOfMessage)
    return [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
}

# Sends one command and returns its result; events and other messages in between are skipped
function Invoke-Cdp($Cdp, [string]$Method, [hashtable]$Params = @{}, [string]$SessionId) {
    $Cdp.NextId += 1
    $id = $Cdp.NextId
    $message = @{ id = $id; method = $Method; params = $Params }
    if ($SessionId) { $message.sessionId = $SessionId }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $message -Depth 10 -Compress))
    # $null: in PowerShell 7 a finished Task yields a VoidTaskResult object
    $null = $Cdp.Socket.SendAsync([System.ArraySegment[byte]]::new($bytes),
        [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $Cdp.Token).GetAwaiter().GetResult()
    while ($true) {
        $text = Receive-CdpText $Cdp
        $answer = $null
        try { $answer = ConvertFrom-Json -InputObject $text } catch { continue }
        if ($null -eq $answer.id -or [long]$answer.id -ne $id) { continue }
        if ($answer.error) { throw "${Method}: $($answer.error.message)" }
        return $answer.result
    }
}

function Get-ChromeLaunchState {
    param(
        [Parameter(Mandatory = $true)][string]$ChromePath,
        [Parameter(Mandatory = $true)][string]$UserDataDir,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 60
    )
    $onWindows = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows
    $all = @('--headless=new', '--no-first-run', '--no-default-browser-check', '--disable-gpu',
             '--enable-automation', '--remote-debugging-port=0', "--user-data-dir=$UserDataDir")
    # Chrome refuses to run as root on Linux unless its sandbox is off
    if (-not $onWindows -and [string](& id -u) -eq '0') { $all += '--no-sandbox' }
    $all += @($Arguments | Where-Object { $_ }) + 'about:blank'

    # Chrome writes the port it picked here; a stale file from an earlier run would point nowhere
    $portFile = Join-Path $UserDataDir 'DevToolsActivePort'
    if (Test-Path -LiteralPath $portFile) { Remove-Item -LiteralPath $portFile -Force }

    $psi = New-Object System.Diagnostics.ProcessStartInfo $ChromePath
    $psi.Arguments = ($all | ForEach-Object { ConvertTo-ProbeArgument $_ }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Chrome on Linux puts its singleton socket in TMPDIR, and a socket path must stay under 108 bytes
    if (-not $onWindows -and $env:TMPDIR -and $env:TMPDIR.Length -gt 60) { $psi.EnvironmentVariables['TMPDIR'] = '/tmp' }
    $proc = [System.Diagnostics.Process]::Start($psi)
    # Both pipes are drained in the background, so Chrome never blocks on a full one
    $null = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()

    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    $socket = $null
    $cts = $null
    $closeSent = $false
    $failure = $null
    try {
        $lines = @()
        while ($lines.Count -lt 2 -or $lines[1] -notlike '/devtools/browser/*') {
            if ($proc.HasExited) { throw "Chrome exited with code $($proc.ExitCode) before DevTools was ready." }
            if ([datetime]::UtcNow -gt $deadline) { throw "No $portFile within $TimeoutSeconds s." }
            Start-Sleep -Milliseconds 100
            # The file may be half written or still locked by Chrome
            try { $lines = @([System.IO.File]::ReadAllLines($portFile) | Where-Object { $_.Trim() }) } catch { $lines = @() }
        }

        $socket = New-Object System.Net.WebSockets.ClientWebSocket
        # A system or environment proxy must not see a connection to 127.0.0.1
        $socket.Options.Proxy = $null
        # One token bounds every DevTools call by the same deadline
        $cts = New-Object System.Threading.CancellationTokenSource ([int][Math]::Max(1000, ($deadline - [datetime]::UtcNow).TotalMilliseconds))
        $cdp = [pscustomobject]@{ Socket = $socket; Token = $cts.Token; NextId = 0; Buffer = (New-Object byte[] 65536) }
        $uri = New-Object System.Uri ('ws://127.0.0.1:{0}{1}' -f $lines[0].Trim(), $lines[1].Trim())
        $null = $socket.ConnectAsync($uri, $cdp.Token).GetAwaiter().GetResult()

        $commandLine = [string[]]@((Invoke-Cdp $cdp 'Browser.getBrowserCommandLine').arguments)
        $product = [string](Invoke-Cdp $cdp 'Browser.getVersion').product
        $targetId = [string](Invoke-Cdp $cdp 'Target.createTarget' @{ url = 'about:blank' }).targetId
        $sessionId = [string](Invoke-Cdp $cdp 'Target.attachToTarget' @{ targetId = $targetId; flatten = $true }).sessionId
        $evaluated = Invoke-Cdp $cdp 'Runtime.evaluate' @{ expression = 'navigator.language'; returnByValue = $true } $sessionId
        $language = [string]$evaluated.result.value

        # Closing through DevTools lets Chrome save Local State; it may drop the connection before it answers
        $closeSent = $true
        try { $null = Invoke-Cdp $cdp 'Browser.close' } catch { }
    } catch {
        $failure = $_.Exception.Message
    } finally {
        if ($socket) { $socket.Dispose() }
        if ($cts) { $cts.Dispose() }
        if (-not $closeSent -or -not $proc.WaitForExit($TimeoutSeconds * 1000)) { Stop-ProbeProcess $proc }
    }
    if ($failure) { throw "Chrome probe failed: $failure$(Get-ProbeOutput $stderr)" }

    # Chrome puts the switches it built from chrome://flags between these two markers
    $begin = [array]::IndexOf($commandLine, '--flag-switches-begin')
    $end = [array]::IndexOf($commandLine, '--flag-switches-end')
    $flagSwitches = @()
    if ($begin -ge 0 -and $end -gt $begin + 1) { $flagSwitches = @($commandLine[($begin + 1)..($end - 1)]) }

    $features = New-Object System.Collections.Generic.List[string]
    foreach ($s in $flagSwitches) {
        if ($s -notmatch '^--enable-features=(.*)$') { continue }
        foreach ($f in $Matches[1] -split ',') {
            # "Feature<Trial" and "Feature:param/value" name the same feature
            $name = ($f -split '[<:]')[0].Trim()
            if ($name -and -not $features.Contains($name)) { $features.Add($name) }
        }
    }

    return [pscustomobject]@{
        Product         = $product
        Arguments       = $commandLine
        FlagSwitches    = [string[]]$flagSwitches
        EnabledFeatures = $features.ToArray()
        Language        = $language
    }
}
